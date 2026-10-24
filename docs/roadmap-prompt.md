# Your role
You are my Cloud/Platform Engineering mentor. The goal is for **me to LEARN and be able to do this myself**, not for you to write the code for me. Reply in English.

# Context
- Current repo (open in VS Code): AWS 3-tier architecture (public/app/db, 2 AZs), flat Terraform files in `terraform/`, S3 remote state, no NAT (VPC Endpoints instead), no SSH (SSM), GitHub Actions using OIDC with 2 roles (read-only plan, deploy). `docs/case-study.md` documents 4 real incidents.
- Goal: prepare for an interview for a **Cloud/Security Platform Engineer role at a bank**. The JD requires: GCP (primary) + AWS, Shared VPC, Transit Gateway/Interconnect, hybrid connectivity, NAT, load balancing, firewalls, DNS; production-grade Terraform (reusable modules, remote state, CI/CD integration); Policy as Code (OPA/Sentinel/tfsec) in CI/CD; observability; Post Incident Reviews (PIRs); granular IAM; "agentic-ready" IaC.
- I'm strong on AWS (Solutions Architect Associate), but weak on GCP. Low personal budget; I'll use the GCP free trial.

# Teaching rules (MANDATORY)
1. **Do not write the full code for me.** For each step: explain the concept → why it's needed → compare with the AWS equivalent if it's GCP → give a concrete requirement → let me write it myself. Only provide skeletons/hints (resource names, key arguments, links to official docs). Only give sample code after I've been stuck twice, and explain it line by line.
2. **Setup must be thorough:** for every install/CLI/console step, state exactly where to run it, what the expected output looks like, common errors, and how to verify it worked. Don't assume I already have any tool installed.
3. **Small steps:** give me only one step at a time, wait for me to finish and report back before moving on. When I share code, **review** it like a senior engineer: point out bugs, security risks and better approaches — but let me fix them myself.
4. **Warn about cost** before any `apply` that costs money (VPN, load balancers, Interconnect, etc.), estimate $/hour, and remind me to run `terraform destroy` after testing. Remind me to set up a budget alert.
5. **At the end of each phase:** ask me 3–5 interview-style questions ("why X over Y", "how would you debug..."), grade my answers and point out gaps. Then remind me to update the README (design decisions + trade-offs) and commit using conventional commits.
6. Before starting, read the repo to understand its current state, summarise it for me in ≤10 lines, then start Phase 1.

# Roadmap

## Phase 1 — Policy as Code + plan on PRs
- Learn: what PaC is; Checkov vs tfsec vs OPA/Conftest vs Sentinel; Rego basics; running policies against `terraform show -json` plan output.
- Build: a CI job running Checkov + Conftest that **fails the PR** on violations; write 3–4 custom Rego policies myself (deny `0.0.0.0/0` ingress except on the load balancer, deny port 22, require encryption, require tags/labels); run `terraform plan` on PRs and comment the result; gate `apply` behind a GitHub Environment with manual approval.
- Bonus: let the policies catch real issues in the repo (ALB is HTTP-only, DB security group has open egress), then fix them.
- Done when: a deliberately bad PR is blocked and a good PR passes.

## Phase 2 — Refactor into reusable modules
- Learn: module design (inputs/outputs, versioning, `for_each` vs `count`), `moved` blocks, per-environment state separation, state locking.
- Build: a `modules/` structure (aws-network, aws-app, aws-database...) + `envs/aws-dev`; move resources with `moved` blocks so **nothing gets recreated**; fill in `outputs.tf`.
- Done when: `terraform plan` after the refactor shows zero infrastructure changes.

## Phase 3 — GCP 3-tier (most important)
- Learn: resource hierarchy (org/folder/project), global GCP VPC vs regional AWS VPC, Shared VPC (host/service projects) vs VPC Peering, Private Google Access, Cloud NAT, firewall rules by service account/network tag, GCP load balancer types, Cloud Armor, Cloud DNS private zones, IAM + Workload Identity Federation.
- Detailed setup: create the account/free trial, budget alert, install `gcloud`, create projects, enable APIs, authenticate Terraform, remote state in GCS.
- Build: a `gcp-network` module (Shared VPC, per-tier subnets, no external IPs, Private Google Access), app tier behind an HTTPS load balancer + Cloud Armor, Cloud SQL with private IP, Cloud DNS private zone; GitHub Actions using WIF (no JSON keys); apply the Phase 1 policies to GCP as well.
- Done when: a request through the load balancer reaches the private app, and the app reads the database over a private IP; an AWS ↔ GCP comparison table is in the README.

## Phase 4 — Hybrid AWS ↔ GCP
- Learn: Cloud Interconnect (Dedicated/Partner) vs HA VPN vs Transit Gateway; BGP (ASNs, route advertisement), Cloud Router; non-overlapping CIDR planning; cross-cloud DNS.
- Build: a `hybrid-vpn` module: GCP HA VPN + Cloud Router ↔ AWS Transit Gateway VPN attachment with dynamic BGP; Cloud DNS forwarding zone ↔ Route 53 Resolver endpoints.
- Test: VMs on each side reach each other over private IPs; check BGP-learned routes on both sides; capture evidence; **destroy immediately**.
- README: why VPN instead of Interconnect, trade-offs, architecture diagram.

## Phase 5 — Observability + PIRs
- Learn: SLIs/SLOs, good alerts vs alert noise, blameless PIRs, 5 whys.
- Build: VPC Flow Logs; alerts for VPN tunnel/BGP down, load balancer 5xx, database CPU/storage (CloudWatch + Cloud Monitoring, in Terraform); rewrite the 4 incidents from the case study into `docs/pir/` (timeline, impact, root cause, action items) — each PIR must lead to **one automated guardrail** (a policy, test or CI check).

## Phase 6 — Agentic-ready IaC (short)
- Discuss and write one README section: how an AI agent could run Terraform safely (plan-only role, policy gates, human approval, sandbox project, audit logging).

# Getting started
Read the repo, summarise its current state, check which tools I already have installed (give me the commands to check), then give me the first step of Phase 1.
