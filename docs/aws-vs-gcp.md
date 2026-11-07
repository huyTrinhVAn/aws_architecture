# AWS vs GCP: what actually works differently

Written from the point of view of someone who knows AWS and is building
the same platform on GCP. **Only differences are listed.** If a concept
maps one-to-one (regions, zones/AZs, object storage, managed MySQL), it's
left out. Networking is covered in full because that's where the mental
model changes most. ⭐ marks things this project ran into.

---

## 1. Networking

### Shape of the network

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **VPC scope** | Regional | **Global**: one VPC spans every region | Multi-region needs no peering inside one VPC. But one bad firewall rule or route also affects every region: **bigger blast radius** |
| **Subnet scope** ⭐ | One AZ | **Regional**: one subnet spans every zone in its region | This project went from 6 subnets on AWS (3 tiers × 2 AZs) to **1 app subnet** on GCP. HA across zones comes from regional instance groups, not from subnet layout |
| **Public / private subnets** ⭐ | A subnet is "public" if its route table points to an IGW; the ALB must sit in public subnets | **No such thing.** Any VM with an external IP can reach the internet through the VPC's default route. The external HTTPS load balancer runs on **Google's edge, outside your VPC** | No public subnet needed for the web tier. "Private" is enforced by **not giving VMs external IPs** (an org policy can forbid them) |
| **DB subnet** ⭐ | RDS lives in your subnets (DB subnet group) | Cloud SQL lives in a **Google-owned VPC**, reached over **private services access**: you reserve a range, Google peers its VPC with yours | No DB subnet to design, but you must reserve a non-overlapping range (`10.20.0.0/20` here), and peering is **non-transitive** (see Phase 4) |
| **Default network** | Default VPC: public subnet per AZ, default SG only allows traffic inside the SG | Default VPC is **auto mode** with firewall rules allowing **SSH, RDP and ICMP from 0.0.0.0/0** plus all internal traffic | Always create projects with `auto_create_network = false` ⭐ and use **custom mode** VPCs |
| **Routes** | Route tables per subnet | Routes belong to the **VPC**; they can be scoped to VMs by network tag | No "associate route table with subnet" step; scoping is by tag instead |
| **Dynamic routing** | TGW / VGW handle BGP | A **Cloud Router** is the BGP speaker for VPN, Interconnect and Cloud NAT | Cloud NAT needs a Cloud Router even though it does no BGP |

### Getting out, and reaching cloud APIs privately

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **NAT** ⭐ | NAT Gateway: an appliance **per AZ**, ~$0.045/h each + $0.045/GB | **Cloud NAT**: software-defined config on a Cloud Router, **regional**. Billed per VM using it + per GB + per NAT IP | No per-AZ fixed cost. With no VMs it costs close to nothing |
| **Private access to cloud APIs** ⭐ | **VPC endpoint per service** (gateway for S3/DynamoDB; interface endpoints billed per AZ per hour) | **Private Google Access**: one subnet flag, all Google APIs, **free** | This project paid ~$58/month for 4 interface endpoints on AWS. The GCP equivalent is `private_ip_google_access = true` |
| **Private access to non-Google services** | Interface endpoints (PrivateLink) | **Private Service Connect**, billed per endpoint like PrivateLink | Private Google Access only covers Google APIs |

### Firewalls

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **Where rules live** ⭐ | Security groups attached to **ENIs**, plus stateless NACLs on subnets | **VPC firewall rules** at the network level, stateful. No NACL equivalent | One rule set to review per VPC |
| **How rules pick targets** | The SG is attached to the instance | Rules **target** VMs by **service account** (preferred) or network tag, or all instances | Targeting by service account ties network access to identity: a VM can't join a rule just by adding a tag |
| **Deny rules and priority** | SGs are allow-only; NACLs have ordered deny rules | Rules have a **priority** (0–65535) and can **allow or deny** | Explicit deny-all baselines are possible ⭐ (`deny-all-ingress` at 65534) |
| **Hidden defaults** ⭐ | A new SG denies inbound and allows all outbound (visible in the console) | Two **implied** rules at priority 65535 that you can't see or delete: deny all ingress, allow all egress | Write the baseline explicitly so it's reviewed and can be logged |
| **Central rules above projects** | SCPs can't express network rules; Firewall Manager can push SGs | **Hierarchical firewall policies** at Org or folder level, evaluated before VPC rules | A security team can enforce "never allow 0.0.0.0/0 on 22" for every project |
| **Load balancer health checks** | ALB health checks come from inside the VPC | Come from **Google ranges `35.191.0.0/16` and `130.211.0.0/22`**, which the firewall must allow | Forget this rule and every backend shows unhealthy |

### Sharing the network across teams

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **Central network, many app teams** ⭐ | **VPC sharing via RAM**: share subnets from a network account to other accounts in the Organization | **Shared VPC**: a host project shares subnets with service projects. Needs an **Organization** | The app team can launch VMs in the subnet but can't touch routes, firewall or NAT. Permission is `compute.networkUser`, grantable **per subnet** ⭐ |
| **Who can create resources in a shared subnet** | Participant accounts the subnet is shared with | Service project principals with `networkUser`, **plus the project's Google APIs service agent** for managed instance groups ⭐ | Easy to miss: the MIG fails to create VMs if the service agent lacks the role |

### Load balancing and egress cost

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **External HTTP(S) LB** | ALB is **regional**, gets IPs per AZ, lives in your subnets | Global external Application LB: **one anycast IP worldwide**, runs on Google's edge | No public subnet, and one IP serves every region |
| **WAF** | AWS WAF attached to the ALB | **Cloud Armor** policy attached to the backend service | Same idea, attached at a different level |
| **Internet egress** | One price list | **Premium tier** (default, rides Google's backbone, pricier) vs **Standard tier** (public internet, cheaper) | GCP egress isn't automatically cheaper |

---

## 2. Resource hierarchy, identity and IAM

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **Isolation unit** ⭐ | **Account**: heavy to create (email, minutes) | **Project**: one Terraform resource, seconds, free | GCP designs use a project per purpose (seed / host / service here) |
| **Grouping** ⭐ | OUs in AWS Organizations | **Folders**; the Org itself only exists for a **verified domain** (Cloud Identity / Workspace) | A personal Gmail can't have an Org, so no Shared VPC. This project bought a domain for Cloud Identity Free |
| **Guardrails above IAM** ⭐ | **SCPs** cap which **IAM actions** an account may use | **Org Policies** restrict **resource configurations** (no SA keys, no external IPs, allowed domains...), regardless of IAM | Different tools: an SCP says "nobody may call X", an Org Policy says "nothing may be configured like Y" |
| **Secure defaults** ⭐ | New accounts have few preventive defaults | New Orgs enforce: **no SA key creation/upload**, domain-restricted sharing, no automatic Editor for default service accounts, uniform bucket access | Workload Identity Federation isn't optional here: it's the only way to authenticate CI |
| **IAM model** | JSON policies with Allow/Deny statements, attached to identities or resources | **Bindings** of role → members on a resource, **inherited down** Org → folder → project → resource | A role at folder level silently applies to every project below ⭐ (why Folder Admin's `setIamPolicy` is a privilege-escalation path) |
| **Explicit deny** | `Deny` in any policy wins | Allow policies can't deny; **IAM Deny policies** are a separate resource | Plan deny guardrails as their own thing |
| **Principal types** ⭐ | IAM users/roles inside one account | Google accounts, groups, service accounts, **`domain:`** (everyone in the domain), `allUsers` | New Orgs grant `domain:` Project Creator and Billing Account Creator. This project removed those |
| **Top admin** ⭐ | Root user, **per account** | **Super Admin** of the Cloud Identity directory. It's **not an IAM role**: it manages users, while GCP access comes from IAM | Org Admin manages IAM but **can't read data** (e.g. list buckets) without granting itself access, which is audited |
| **Resource creator** ⭐ | Creating an account doesn't make you admin inside it | **Whoever creates a project becomes its Owner** | The account that ran Terraform is Owner of every project it created |

## 3. Credentials and sessions

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **CLI vs SDK credentials** ⭐ | `aws configure` credentials are shared by the CLI and Terraform | **Two separate logins**: `gcloud auth login` (CLI) and `gcloud auth application-default login` (**ADC**, used by Terraform/SDKs) | "gcloud works but Terraform can't find credentials" is the classic symptom |
| **Quota project** ⭐ | Not a concept | User ADC calls are billed/quota'd to a **quota project** (`set-quota-project`) | Without one, some APIs fail or warn |
| **Session length** ⭐ | Keys don't expire; SSO sessions do | Cloud Identity **session control** forces re-authentication | Shows up as `invalid_rapt` in Terraform; the fix is logging in again. CI uses WIF, so it's never affected |
| **CI federation** | OIDC provider + `AssumeRoleWithWebIdentity`, scoped by the trust policy's `sub` | **Workload Identity Federation**: pool + provider + attribute conditions, then impersonate a service account | Same idea, more parts (Phase 3.8) |

## 4. Billing

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **Who pays** ⭐ | The account (or the Organization's management account) | A **billing account**, a separate resource that projects are **linked** to | A project can move between billing accounts. Linking needs `billing.user` on the billing account |
| **Activation** ⭐ | Card on sign-up | Free trial (US$300 / 90 days) may require a **one-time prepayment** for some new accounts | This account needed A$40 before the billing account went active |
| **Free tier for the DB** | RDS `db.t4g.micro` free for 12 months | **No Cloud SQL free tier** | The GCP database is the main running cost |

## 5. Terraform and tooling

| Topic | AWS | GCP | Why it matters |
|---|---|---|---|
| **State backend locking** ⭐ | `backend "s3"` needs `use_lockfile = true` (or DynamoDB before Terraform 1.10) | `backend "gcs"` **locks automatically** | One less setting to forget |
| **Tags vs labels** | Tags: free-form keys/values | **Labels**: lowercase letters, digits, `-` and `_` only. GCP also has **"tags" (Resource Manager tags)**, a different feature used in IAM conditions and firewall policies | Don't reuse AWS tag names as-is (`ManagedBy` → `managed-by`) |
| **Console scope** ⭐ | Shows the signed-in account's resources | Resource pages (Storage, Compute...) need a **project selected**; admin pages (IAM, Org Policies, Manage resources) work at Org/folder level | "I can't see anything" usually means no project is selected |
| **Inventory across projects** | Config aggregator / Resource Explorer | **Cloud Asset Inventory** at Org or folder level | Answers "which buckets exist anywhere in the company?" |
