# Policy as Code

Every change to `terraform/` is checked by two independent policy layers
before it can reach AWS, and nothing is applied without a human approval.

## In short

**Terms**
- **Policy as Code:** security and compliance rules written as code, versioned, reviewed and enforced automatically in CI, instead of living in a wiki or a reviewer's head.
- **Checkov:** an open-source scanner with ~1,000 built-in rules. It reads `.tf` files and flags common misconfigurations.
- **OPA (Open Policy Agent):** a general-purpose policy engine. **Rego** is its rule language.
- **Conftest:** a CLI that runs Rego policies against config files. Here, against the Terraform plan JSON.

**What I built**
- Checkov runs on every PR. I triaged the first scan's 41 failures: fixed 16, and documented every remaining exception inline with a reason.
- I wrote my own Rego policies, run on the plan JSON: only the ALB may face the internet (ports 80/443 only), no SSH/RDP from any source, encryption at rest, required tags. They have 21 unit tests.
- Every PR gets a `terraform plan` posted as a comment, using a read-only OIDC role.
- `apply` runs only after manual approval in a GitHub Environment. The AWS role trusts only that environment's OIDC claim, so AWS enforces the gate, not just the workflow file.
- Branch protection makes all checks required. A test PR opening SSH to the internet was blocked by both layers.

**How the two layers relate:** both are required checks, so a PR must pass **both**. Checkov gives breadth (generic rules I didn't have to write). Rego gives precision: my organisation's own rules, checked on the final plan values Terraform will actually create.

**How to stop people bypassing the rules:** a `#checkov:skip` comment can silence Checkov, but not the Rego policies, which only change through `policy/`. In production I'd add `CODEOWNERS` so the security team must approve changes to `policy/` and any new skip.

**Biggest finding:** following up an "open egress" warning on the database security group revealed that the S3 gateway endpoint had no policy and was routed to the db subnet. A compromised DB host could have copied data to *any* S3 bucket without internet access. I fixed it in depth: removed the route, added an endpoint policy and removed the db egress.

```
PR opened ──► terraform-check   fmt + validate (no AWS access)
          ├─► checkov           ~1,000 built-in rules against the .tf files
          ├─► policy-tests      unit tests for our own Rego policies
          └─► terraform-plan    plan (read-only role) ──► conftest on plan JSON ──► plan posted as PR comment

merge to main ──► same checks ──► terraform-apply  ⏸ waits for approval (GitHub Environment "production")
                                                    └─► re-plan ──► conftest ──► apply (apply role)
```

## Why two layers

| | Checkov | Conftest (OPA/Rego) |
|---|---|---|
| Input | `.tf` source files | `terraform show -json` plan output |
| Rules | ~1,000 generic, written by Checkov | ours, specific to this organisation |
| Sees | code as written (variables unresolved) | final values after variables, `count`, `default_tags` |
| Good for | broad coverage with zero effort | rules no generic tool knows: "only the ALB may face the internet" |

Checkov catches the long tail of known misconfigurations; Conftest enforces
our own rules against what Terraform will *actually* create.

## Custom policies (`policy/`)

| Policy | Denies |
|---|---|
| `security_groups.rego` | ingress from `0.0.0.0/0` or `::/0` on any SG not tagged `Exposure=internet-facing`; anything but ports 80/443 open to the internet even on that SG; any ingress covering 22 (SSH) or 3389 (RDP), from any source |
| `encryption.rego` | RDS or EBS storage without encryption; an S3 bucket with no server-side encryption configuration |
| `tags.rego` | a taggable AWS resource missing `Project` or `ManagedBy` |

Each policy has a `_test.rego` file with good and deliberately bad inputs.
The tests caught a real bug while these policies were written: a helper
returned *undefined* instead of `false` for untagged security groups, which
made OPA silently skip every non-ALB group. The policy passed the real plan
while checking almost nothing.

Run locally:

```powershell
.\.venv\Scripts\python.exe -m checkov.main --config-file .checkov.yaml
conftest verify --policy policy
cd terraform
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
conftest test plan.json --policy ../policy --all-namespaces
```

On Windows, call Checkov as `python -m checkov.main` from the venv: the
`checkov.cmd` wrapper picks up whichever Python is first on `PATH`.

## Triage of the first Checkov scan

The first scan reported **123 passed / 41 failed**. Each finding was sorted
into one of three categories:

- **Fixed:** a real issue, fixed in code.
- **Skipped, tracked:** a real issue whose fix belongs to a later step.
- **Skipped, accepted risk / false positive:** a deliberate trade-off, or the rule doesn't fit this design.

Skips are inline `#checkov:skip=ID:reason` comments on the resource itself,
never a global ignore list, so every exception is reviewed in the PR that
introduces it. After triage: **146 passed / 0 failed / 26 skipped.** The
26th skip, `CKV_AWS_274`, is new and covers the apply role (see below).

### Fixed (16)

| Check | Resource(s) | Fix |
|---|---|---|
| `CKV_AWS_382` ×4 | alb, app, db, vpc_endpoints SGs | Egress narrowed to the exact next hop: ALB → app subnets on the app port; app → endpoint SG on 443, S3 prefix list on 443, db subnets on 3306; db and endpoint SGs get `egress = []` |
| `CKV_AWS_23` ×4 | same four SGs | every rule has a description |
| `CKV2_AWS_12` | VPC default SG | adopted with no rules, so anything that falls back to it gets no traffic |
| `CKV_AWS_130` ×2 | public subnets | `map_public_ip_on_launch = false` (the ALB doesn't need it) |
| `CKV_AWS_131` | ALB | `drop_invalid_header_fields = true` |
| `CKV_AWS_226` | RDS | `auto_minor_version_upgrade = true` |
| `CKV2_AWS_60` | RDS | `copy_tags_to_snapshot = true` |
| `CKV_AWS_300` | receipts bucket | abort incomplete multipart uploads after 7 days |
| `CKV2_AWS_61` | deploy bucket | lifecycle rule added (abort incomplete uploads after 1 day) |

**The finding with the biggest impact wasn't the one Checkov reported.**
Following up `CKV_AWS_382` on the db SG showed that the S3 *gateway
endpoint* was attached to the db route table and had **no endpoint policy**.
Together with open egress, a compromised db host had a path to copy data
into *any* S3 bucket in the region, including an attacker's, with no
internet access needed. Fixed in depth:

- the db route table no longer has an S3 route at all
- the endpoint policy only allows the project's two buckets plus the AWS-operated AL2023 package repo
- the db SG has no egress

### Skipped, tracked (8): real issues, scheduled

| Check | Why it's not fixed yet |
|---|---|
| `CKV_AWS_2`, `CKV_AWS_103`, `CKV2_AWS_20` | HTTPS listener + HTTP→HTTPS redirect need an ACM certificate for the project domain (DNS validation record at the registrar). **Next step after Phase 1.** |
| `CKV2_AWS_11` | VPC Flow Logs: roadmap Phase 5 (observability) |
| `CKV_AWS_91`, `CKV_AWS_18` ×2, `CKV_AWS_129` | ALB access logs, S3 access logs, RDS log exports: Phase 5, alongside a log bucket and retention decision |

### Skipped, accepted risk (13): cost or lab trade-offs

| Check | Trade-off | Production answer |
|---|---|---|
| `CKV_AWS_157` | single-AZ RDS: Multi-AZ roughly doubles cost | Multi-AZ, always |
| `CKV_AWS_293`, `CKV_AWS_150` | no deletion protection on RDS/ALB: the lab is destroyed after each session | on |
| `CKV2_AWS_28` | no WAF on the ALB (~$5/month + rules) | WAF with managed rule groups |
| `CKV_AWS_118` | no RDS enhanced monitoring (extra cost) | on |
| `CKV_AWS_161` | no RDS IAM auth: the app uses a Secrets Manager-held password | IAM auth or rotated secrets |
| `CKV_AWS_149` | Secrets Manager uses the AWS-managed key | customer-managed KMS key |
| `CKV2_AWS_57` | no secret rotation (needs a rotation Lambda + app reconnect logic) | rotation on |
| `CKV_AWS_145` ×2 | S3 uses SSE-S3, not SSE-KMS | SSE-KMS with a CMK for classified data |
| `CKV_AWS_144` ×2 | no cross-region replication (doubles storage) | depends on the data's RPO |
| `CKV_AWS_21` | deploy bucket unversioned: CI rebuilds the bundle every push | same |

### Skipped, false positive (4)

| Check | Why it doesn't apply |
|---|---|
| `CKV_AWS_260` | port 80 open to the world on the **internet-facing ALB**: that's its job. Our own Rego policy enforces the stricter rule: *only* this SG, *only* 80/443 |
| `CKV2_AWS_62` ×2 | S3 event notifications: there's no consumer to notify |
| `CKV_AWS_378` | HTTP target group: TLS terminates at the ALB, and the ALB→instance hop stays in private subnets |

## How the apply gate works

The approval is enforced by AWS, not only by the workflow file:

1. `terraform-apply` declares `environment: production`. GitHub won't start
   the job until a required reviewer approves it.
2. Only a job in that environment receives an OIDC token whose `sub` claim
   ends in `:environment:production`.
3. The `github-actions-apply` role's trust policy accepts **only** that
   claim. A workflow edited to skip the environment can't assume the role.

The apply role has `AdministratorAccess` (skip `CKV_AWS_274`), because this
Terraform creates IAM roles, VPCs and RDS. The controls are on *who can
assume* the role, not inside it. The next hardening step is a permissions
boundary limiting IAM changes to the project's own role names.

The apply job re-plans instead of reusing the PR's plan file: saved plans
contain secret values (the DB password) in plaintext, and workflow
artifacts are readable by anyone with read access to the repo. The policy
check runs again on the exact plan being applied.

## One-time setup

1. **Create the CI roles** (IAM only, free). CI can't assume roles that
   don't exist yet, so this first apply is local, with your admin
   credentials:
   ```powershell
   cd terraform
   terraform apply `
     -target="aws_iam_openid_connect_provider.github" `
     -target="aws_iam_role.github_actions_ci" `
     -target="aws_iam_role_policy_attachment.github_actions_ci_readonly" `
     -target="aws_iam_role_policy.github_actions_ci_state_lock" `
     -target="aws_iam_role.github_actions_apply" `
     -target="aws_iam_role_policy_attachment.github_actions_apply_admin"
   ```
2. **GitHub → Settings → Environments → New environment** `production`:
   - Required reviewers: yourself. This is free on public repos; private repos need a paid plan.
   - Deployment branches: `main` only.
3. **GitHub → Settings → Rules → Rulesets** (or Branches → branch
   protection) for `main`: require a PR, and require the status checks
   `terraform-check`, `checkov`, `policy-tests` and `terraform-plan`.
   **Without this, a failing check is only a red ✗ and doesn't block the
   merge.**
4. **Settings → Secrets and variables → Actions → Variables:**
   `ENABLE_TERRAFORM_APPLY` = `true`. Only do this after step 2.

⚠️ Approving `terraform-apply` creates the **whole stack**: ALB, RDS, 2×EC2
and 8 interface-endpoint ENIs, roughly **$0.15/hour (~$3.50/day)**. Destroy
it after testing. A full `terraform destroy` also deletes the CI roles, so
repeat step 1 before the next PR.
