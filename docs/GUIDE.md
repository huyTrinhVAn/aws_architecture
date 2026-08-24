# Project Guide: Highly-Available, Cost-Optimized Web App on AWS

## 0. Goal and why this project

The AWS Solutions Architect job description you're targeting asks for:
- A programming language (Python/Ruby/Node.js/C#/C++)
- Experience with 2+ of: networking fundamentals, security, storage or databases, operating systems (Unix/Linux/Windows)
- Preferred: experience implementing a cloud-based technology solution, cloud architecture, systems design, DevOps

This project is designed so that every architectural decision has a clear reason tied to **cost or security** — because that is literally the job of an AWS SA: help customers deploy the most secure, scalable architecture while spending as little time and money as possible. In an interview, you won't say "I built a VPC" — you'll say "I removed the NAT Gateway to save ~$32/month and used SSM Session Manager instead, which also improved the security posture." That's a story with depth.

**How to use this guide:** for each phase, read the "Concepts to understand" section first, look them up in AWS docs yourself, write the Terraform yourself, and only then compare against a reference implementation if you get stuck. Don't copy code before you've tried.

---

## 1. Overall architecture

```
                         Internet
                            |
                      +-----v-----+
                      |    ALB    |  (public subnets, 2 AZs)
                      +-----+-----+
                            | :8080
        +-------------------+-------------------+
        |           Private App Subnets          |
        |  +---------+  +----------+             |
        |  | EC2 (OD)|  | EC2(Spot)|  Auto Scaling|
        |  +----+----+  +----+-----+  Group       |
        +-------+------------+---------------------+
                |            |
        +-------v------------v----+        +-------------------+
        |   VPC Endpoints (SSM,   |        |   VPC Endpoints    |
        |   S3, DynamoDB gateway) |        |   replace NAT       |
        +--------------------------+        +-------------------+
                |
        +-------v---------+
        |  Private DB      |
        |  Subnets: RDS    |
        +------------------+
```

No NAT Gateway, no bastion host, no SSH key anywhere in this architecture.

---

## 2. Phased roadmap

### Phase 0 — Setup (half a day)
**Tasks:**
1. Create a dedicated AWS account for this lab (not a company account), enable MFA on the root user.
2. Create an IAM user for Terraform (never use root). Attach `AdministratorAccess` for the lab only — later, scoping this down to least privilege is a good follow-up exercise.
3. **Most important step before anything else:** in Billing → Budgets, manually create a $10-20/month budget through the Console as a safety net that's independent of any bug in your own Terraform code.
4. Install `terraform` and the `aws` CLI, run `aws configure`.

**Why set up the budget manually first:** if your Terraform code has a bug and accidentally creates an expensive resource, you still get an alert that doesn't depend on the code that caused the problem.

---

### Phase 1 — Networking fundamentals
**Concepts to understand first:**
- How a VPC, CIDR block, subnet, and route table relate (a subnet is "public" or "private" purely because of its route table — not an inherent property of the subnet itself)
- Why split into three subnet tiers (public / app / db) instead of one
- Internet Gateway vs. NAT Gateway — which handles which direction of traffic

**Tasks:**
1. Sketch your own CIDR layout (e.g. VPC `10.0.0.0/16`, public `10.0.0.0/24` and `10.0.1.0/24`, app `10.0.10.0/24`/`10.0.11.0/24`, db `10.0.20.0/24`/`10.0.21.0/24`) spread across 2 AZs.
2. Write Terraform to create: the VPC, an Internet Gateway, 6 subnets, 3 route tables, and their associations.
3. **Don't create a NAT Gateway yet** — Phase 3 replaces it with VPC Endpoints.

**Further reading:** [Amazon VPC User Guide – Subnets](https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html)

**Done when:** `terraform apply` succeeds, and the Console shows the subnet/route-table layout you designed.

---

### Phase 2 — Security groups and SSH-less instance access
**Concepts to understand:**
- Security Group (stateful, allow-only) vs. NACL (stateless, allow+deny, applies per subnet)
- Least privilege: each tier's security group should only allow traffic from the tier in front of it, never a broad CIDR
- AWS Systems Manager Session Manager: how it fully replaces a bastion host/SSH — it requires the instance to have an IAM role with the `AmazonSSMManagedInstanceCore` policy, and (without a NAT Gateway) VPC Interface Endpoints for `ssm`, `ssmmessages`, and `ec2messages`

**Tasks:**
1. Write three security groups: `alb-sg` (80/443 from the internet), `app-sg` (app port only from `alb-sg`), `db-sg` (DB port only from `app-sg`).
2. Create an IAM role for EC2 with `AmazonSSMManagedInstanceCore` attached.
3. Launch a single `t4g.micro` EC2 instance in a private subnet and connect via Session Manager (Console → EC2 → Connect → Session Manager) — **no key pair, no port 22 open anywhere.**

**Done when:** you can connect to an EC2 instance in a private subnet with no SSH key and no route to the internet.

---

### Phase 3 — Where networking meets cost optimization: VPC Endpoints instead of NAT Gateway
This is the most valuable part of the project to talk about in interviews.

**Concepts to understand:**
- NAT Gateway: ~$0.045/hour (~$32/month) plus per-GB data processing charges — running 24/7 whether or not it's used
- Gateway VPC Endpoint (S3, DynamoDB): **free**, attaches directly to a route table
- Interface VPC Endpoint (SSM, Secrets Manager, ...): billed hourly + data (~$0.01/hour per AZ), far cheaper than a NAT Gateway if you only need a handful of specific AWS services
- The trade-off: if your app needs to call external (non-AWS) APIs from a private subnet, you still need a NAT Gateway or an egress path through a public subnet

**Tasks:**
1. Add a Gateway Endpoint for S3 and one for DynamoDB to the app/db subnets' route tables.
2. Add Interface Endpoints for `ssm`, `ssmmessages`, and `ec2messages` (if you temporarily used a NAT Gateway in Phase 2 to test SSM, remove it now and rely on the endpoints instead).
3. Delete the NAT Gateway/Elastic IP if you created one, and compare the before/after bill in Cost Explorer (even after just a few hours, the NAT line item disappears).
4. Record in a `docs/cost-optimization.md` you write yourself: a table comparing estimated monthly cost of NAT Gateway vs. VPC Endpoints for your setup.

**Further reading:** [VPC Endpoints pricing](https://aws.amazon.com/privatelink/pricing/), and the AWS Architecture Blog post on reducing cost with VPC endpoints.

**Done when:** you can explain, with concrete numbers (not just "it's cheaper"), how much removing the NAT Gateway saves per month for your architecture.

---

### Phase 4 — The app: a Personal Budget Tracker API

Rather than deploying a bare health-check stub, the app you host on this infrastructure is a small **Budget Tracker API** — deliberately thematic: the app that runs on your cost-optimized infrastructure is itself about tracking spend. It gives the ALB, ASG, RDS, and S3 tiers real work to do, and gives you a second, independent talking point in interviews ("I also built the API layer, with a real relational schema").

**Design it yourself before writing code.** A reasonable starting scope:
- **Data model (in RDS):** a `users` table (even a single hardcoded user is fine for a lab), a `categories` table (Food, Transport, Rent, ...), and an `expenses` table (`amount`, `category_id`, `note`, `receipt_s3_key`, `created_at`).
- **API endpoints:** `POST /expenses` (create), `GET /expenses` (list, with filters by category/date range), `GET /expenses/summary` (totals grouped by category and by month), `POST /expenses/:id/receipt` (upload a receipt image/PDF, stored in the S3 bucket from Phase 5), `GET /health` (for the ALB health check).
- **Keep the framework choice consistent with the language you listed on your resume for this role** (e.g. Flask or FastAPI in Python, or Express in Node.js) — pick one and stick with it end to end.

**Concepts to understand for the infrastructure hosting it:**
- Graviton (ARM, `t4g.*`) is roughly 20% cheaper than the equivalent Intel (`t3.*`) instance, but requires an ARM-compatible AMI and dependencies
- Spot Instances: 60-90% cheaper than On-Demand but can be interrupted — only suitable for a stateless tier backed by auto scaling (your API is stateless as long as it doesn't store anything on local disk — all state lives in RDS/S3)
- Mixed Instances Policy on an Auto Scaling Group: run a guaranteed On-Demand baseline, fill the rest of capacity with Spot
- Target Tracking Scaling Policy: scale on actual CPU load instead of running `max_size` capacity around the clock

**Tasks:**
1. Design and build the Budget Tracker API locally first (against a local Postgres/MySQL) before touching AWS — validate the app logic in isolation.
2. Create a Launch Template using an Amazon Linux 2023 ARM64 AMI, instance type `t4g.micro`, with user-data that installs and starts your app.
3. Create an ALB (in the public subnets) with a Target Group and an HTTP listener forwarding to the app port, health-checked against `/health`.
4. Create an Auto Scaling Group with a `mixed_instances_policy` (on-demand base = 1, everything above that is Spot).
5. Add a Target Tracking policy on CPU at 60%.

**Done when:** the ALB's DNS name serves your API, you can create an expense and see it come back from `GET /expenses`, killing one instance triggers the ASG to replace it, and you can see in the Console which instances are Spot vs. On-Demand.

---

### Phase 5 — Storage and database with a cost strategy
**Concepts to understand:**
- S3 storage classes: Standard → Standard-IA → Glacier, with a lifecycle rule automatically transitioning objects by age
- RDS: `db.t4g.micro` (Graviton) is cheaper than `db.t3.micro`, and falls under the 12-month free tier for a new account
- Multi-AZ RDS: roughly doubles the cost — only enable it when you have a real HA requirement; this is a trade-off you should be able to justify, not something you turn on "just in case"
- Secrets Manager: never hard-code the DB password in application code or in Terraform state as plaintext you rely on — the instance should read the secret at runtime via its IAM role

**Tasks:**
1. Create an S3 bucket for the Budget Tracker's uploaded receipts, with versioning, encryption, and a lifecycle rule (30 days → IA, 90 days → Glacier) — this bucket now holds real objects from Phase 4's `POST /expenses/:id/receipt` endpoint, so the lifecycle transition is something you can actually observe happening to real data instead of an empty bucket.
2. Create a single-AZ `db.t4g.micro` RDS instance, with its DB subnet group in the db subnets, and a security group that only allows traffic from `app-sg`. Run your `users`/`categories`/`expenses` schema against it.
3. Store the credentials in Secrets Manager, and grant the app's IAM role permission to read exactly that one secret (not `secretsmanager:*`).

**Done when:** the app EC2 instance can read the secret and connect to RDS, an uploaded receipt lands in S3 under the correct key, and you (the operator) never had to look at the DB password anywhere outside the Secrets Manager console.

---

### Phase 6 — Automation in Python (demonstrates programming skill)
**Task:** write a `scripts/cost_audit.py` script using `boto3` that scans for:
- EBS volumes in the `available` state (not attached to any instance) — wasted spend
- Elastic IPs not associated with any instance
- EC2 instances with average CPU under 5% over the last 7 days (via CloudWatch) — downsizing candidates
- S3 buckets with no lifecycle policy configured

Print a report table and estimate the dollar savings from cleaning these up.

**This is exactly the "programming language experience" line in the JD** — not just writing IaC, but writing an operational tool.

---

### Phase 7 — Teardown and writing up the case study
1. Run `terraform destroy` for everything, and confirm in the Billing Console that nothing is still running.
2. Write a one-page case study using the STAR format, ready to use in interviews:
   - **Situation:** a hypothetical customer/project needing a 3-tier web app on a tight budget
   - **Task:** design a highly available, secure, cost-optimized architecture
   - **Action:** list 3-4 decisions with real numbers (removing NAT saved $X, Spot+Graviton saved Y%, S3 lifecycle reduced storage cost by Z%)
   - **Result:** total estimated monthly cost compared to a "default," non-optimized architecture

---

## 3. How to talk about this project in an AWS SA interview

For a question like "Tell me about a time you optimized cost for a customer" — answer using Phase 3 and Phase 4 above, with concrete numbers. For "Design the network for a 3-tier application" — redraw the diagram in section 1 and walk through each route table's purpose.

## 4. Reference material to read alongside this project

- AWS Well-Architected Framework — the **Cost Optimization** and **Reliability** pillars
- The AWS Certified Solutions Architect – Associate exam guide (even without taking the exam, its topic list matches almost exactly what this JD is asking for)
- The Terraform AWS Provider documentation for each resource, whenever you're unsure of the syntax

## 5. Suggested repository layout (create these as you reach each phase)

```
aws_sa_project/
├── docs/
│   ├── GUIDE.md                 (this file)
│   ├── cost-optimization.md     (you write this in Phase 3)
│   └── case-study.md            (you write this in Phase 7)
├── terraform/
│   ├── modules/
│   │   ├── networking/
│   │   ├── security/
│   │   ├── compute/
│   │   ├── database/
│   │   ├── storage/
│   │   └── cost_controls/
│   └── (root main.tf, variables.tf, outputs.tf)
└── scripts/
    └── cost_audit.py             (Phase 6)
```

Don't create these folders ahead of time — create each one when you reach the corresponding phase. Building the structure as you go, rather than scaffolding it all up front, is part of what makes the knowledge stick.
