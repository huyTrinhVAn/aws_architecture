# Case Study: Cost-Optimized AWS Architecture with Automated CI/CD

## Situation

I wanted a portfolio project that could stand up to real AWS Solutions Architect interview questions — not a tutorial followed step by step, but something where I had made every architectural trade-off myself and could defend it with numbers. The brief I set for myself: design and run a 3-tier web application on AWS where cost and security decisions are explicit and measurable, not assumed.

## Task

Build a highly-available, cost-optimized web application — a small "Budget Tracker" API — on infrastructure that:
- Never relies on a NAT Gateway or SSH access, by design, not by exception.
- Uses IAM least-privilege throughout, including in the CI/CD pipeline itself.
- Is fully defined as code (Terraform) with remote state, so the pipeline can review it safely.
- Produces real evidence — applied resources, real traffic, real dollar-relevant decisions — rather than a diagram that was never run.

## Action

**Networking.** Designed a 3-tier VPC (public / app / db) across 2 AZs. The app and db route tables were built with no `0.0.0.0/0` route from the start — private subnets have zero path to the internet, period. Instead of a NAT Gateway (~$32/month fixed cost, regardless of usage), app instances reach exactly the AWS services they need — S3, Secrets Manager, and Systems Manager — through VPC Endpoints. The S3 Gateway Endpoint is free outright, which matters most since it carries the highest-volume traffic (deployment bundles, receipt uploads). The four Interface Endpoints, run across 2 AZs for redundancy, actually come out *more expensive* on raw hourly cost than the NAT Gateway they replaced (~$58/month vs. ~$32/month) — the full arithmetic is in `docs/cost-optimization.md`. The decision held anyway, because the real driver was removing SSH/bastion access entirely, not the interface endpoints' price tag; a cost-sensitive variant would drop to 1 AZ and undercut NAT outright.

**Access.** Removed SSH entirely. Every instance is managed through AWS Systems Manager Session Manager, authorized via IAM role rather than a distributed SSH key — no bastion host, no open port 22, no key rotation problem to manage.

**Compute.** The app tier runs on Graviton (`t4g.micro`) instances in a mixed-instances Auto Scaling Group — one guaranteed On-Demand instance plus Spot for anything above that — with a CPU-based target-tracking policy instead of a fixed instance count. This wasn't just configured; it was *observed* scaling in automatically when real CPU utilization sat at 0.8%, which then surfaced a second decision: Terraform and the autoscaler both trying to own `desired_capacity` had to be reconciled with a `lifecycle { ignore_changes }` block, or every `apply` would fight the autoscaler's own decisions.

**Identity in CI/CD.** GitHub Actions never holds an AWS access key. Each workflow run exchanges a short-lived, signed OIDC token for temporary credentials via `sts:AssumeRoleWithWebIdentity`, scoped to this exact repository and branch. Rather than one convenient role, the pipeline uses two: a read-only role for `terraform plan` (so the account state can't be leaked to a build log) and a separate, narrower role that can only `PutObject` into one deployment bucket — a compromised build step in one job still can't touch the other's blast radius.

**Diagnosing real failures.** Several incidents came up during the build, each root-caused with evidence rather than guesswork:
- An `AssumeRoleWithWebIdentity` trust-policy mismatch that standard documentation didn't cover — resolved by reading the actual `AccessDenied` event in CloudTrail, which showed GitHub's OIDC `sub` claim includes immutable numeric IDs (`repo:OWNER@ID/REPO@ID:...`) that most examples omit.
- A deployment bundle built for Python 3.12 that silently dropped a conditional dependency (`importlib-metadata`) needed on the AMI's actual runtime, Python 3.9.25 — confirmed via SSM, not assumed from documentation.
- A `user_data` script that hung indefinitely rather than failing loudly, traced to a missing VPC Interface Endpoint for Secrets Manager that Phase 3's endpoint list hadn't anticipated needing.
- A free-tier account limit rejecting the originally planned RDS backup retention period.

**Operational tooling.** Wrote a `boto3` script (`scripts/cost_audit.py`) that scans the account for exactly the kind of waste that accrues quietly — unattached EBS volumes, unassociated Elastic IPs, idle EC2 instances by measured CloudWatch CPU, and S3 buckets with no lifecycle policy — rather than treating "cost optimization" as a one-time design decision.

## Result

The full stack was applied to a real AWS account and verified end-to-end: a request through the Application Load Balancer's public DNS name reached a Flask app on a private Graviton instance, which read its database credentials from Secrets Manager over a private VPC Endpoint (never the public internet) and wrote to a real RDS instance — confirmed by querying the data back out. The `cost_audit.py` tool, run against the live account, found genuine findings: one idle instance at 0.8% average CPU and two S3 buckets missing a lifecycle policy.

The entire environment was torn down cleanly afterward — `terraform destroy` plus one manual step to empty a non-empty S3 bucket Terraform wouldn't delete by default — verified against the account with zero EC2, RDS, load balancer, or NAT resources left running.

**What I'd say in one sentence:** every dollar this architecture doesn't spend, and every credential it doesn't need to store, is the result of a specific, defensible trade-off — not a default.
