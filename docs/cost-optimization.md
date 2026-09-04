# Cost Optimization: NAT Gateway vs. VPC Endpoints

Phase 3's decision was to remove the NAT Gateway entirely and reach AWS services (S3, SSM, SSM Messages, EC2 Messages, Secrets Manager) through VPC Endpoints instead. This document runs the actual numbers for *this* project's configuration — and the honest answer is more nuanced than "NAT is expensive, endpoints are free."

List prices below are for `us-east-1` at the time of writing; always check the [current AWS pricing pages](https://aws.amazon.com/vpc/pricing/) before quoting these in a real proposal.

## List pricing

| | Hourly (per unit) | Data processing |
|---|---|---|
| NAT Gateway | $0.045/hour | $0.045/GB |
| Interface VPC Endpoint | $0.01/hour **per Availability Zone** | $0.01/GB |
| Gateway VPC Endpoint (S3, DynamoDB) | $0 | $0 |

## What this project actually deployed

- 1 NAT Gateway would have been a single resource: **$0.045/hr → ~$32.85/month** fixed, regardless of traffic.
- Instead, this project deployed 4 Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`, `secretsmanager`), each spanning **2 AZs** for the app subnets — that's 8 billed endpoint-AZ units.
- Plus 1 Gateway Endpoint for S3 — free, no hourly charge, no data charge, ever.

| Component | Monthly fixed cost |
|---|---|
| 4 Interface Endpoints × 2 AZs × $0.01/hr × 730 hr | **$58.40** |
| S3 Gateway Endpoint | **$0** |
| **Total (this project)** | **$58.40** |
| *For comparison: 1 NAT Gateway* | *$32.85* |

## The honest verdict

On **fixed hourly cost alone, this project's VPC Endpoint setup is more expensive than a single NAT Gateway would have been** — not less. Four interface endpoints across two AZs adds up faster than one NAT Gateway's flat fee. Anyone citing "VPC Endpoints instead of NAT Gateway" as an unconditional cost win hasn't done this arithmetic; it depends entirely on how many interface endpoints you need and across how many AZs.

What actually justifies the decision here is three things that don't show up in a one-line hourly comparison:

1. **S3 traffic is completely free through the Gateway Endpoint — hourly *and* per-GB.** The deployment bundle download (~13MB per instance launch) and every receipt upload pay nothing. Through a NAT Gateway, that same traffic would cost $0.045/GB on top of the NAT's own hourly fee. As traffic volume grows, this gap only widens in the Gateway Endpoint's favor — the crossover point where "endpoints save money" becomes true depends on how much S3 traffic the workload generates, which a real capacity plan would model rather than assume.
2. **A single-AZ Interface Endpoint deployment would have been cheaper than NAT outright.** Deploying the 4 interface endpoints in only 1 AZ instead of 2 cuts that line from $58.40/month to **$29.20/month** — below the NAT Gateway's $32.85. The trade-off: if that one AZ has an issue, instances in the *other* AZ temporarily lose access to SSM and Secrets Manager (though not to the app itself, which keeps serving traffic through the ALB). This project chose 2-AZ redundancy for management-plane access; a cost-sensitive production environment might reasonably choose 1 AZ instead and accept that narrower risk.
3. **The security posture (no bastion host, no SSH keys, no open port 22, IAM-scoped and session-logged access) has value that doesn't appear on the AWS bill at all**, and was the primary reason for removing NAT/SSH access in Phase 2-3, independent of which option happened to be cheaper.

## Recommendation

Don't default to "VPC Endpoints are cheaper" as a blanket rule — run the actual arithmetic for the specific number of interface endpoints and AZs a workload needs, the same way this document does. For this project specifically:
- Keep the S3 Gateway Endpoint regardless — it is strictly free and strictly better than a NAT Gateway for that traffic.
- For the Interface Endpoints, the deciding factor isn't cost at this traffic volume — it's whether losing SSM/Secrets Manager access in one AZ during an AZ-level event is acceptable. Choose 2-AZ for a production system where that access matters during an incident; choose 1-AZ if the ~$29/month difference matters more than that specific risk.
