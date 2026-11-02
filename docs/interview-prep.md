# Interview prep

Questions a platform-engineering interviewer is likely to ask about this
project, with model answers I can say out loud in about a minute. Each
answer is grounded in something I actually built or debugged here.
Details live in [policy-as-code.md](policy-as-code.md) and
[terraform-modules.md](terraform-modules.md).

Updated at the end of every roadmap phase.

---

## Phase 1: Policy as Code

### Q1. Checkov already scans the Terraform code. Why also run Rego policies against the plan JSON?

> Checkov reads the `.tf` source, where variables, `count`/`for_each` and
> `default_tags` aren't resolved yet. The plan JSON contains the **final
> values** Terraform will actually create. Example: my `Project` and
> `ManagedBy` tags come from the provider's `default_tags`, so they never
> appear in the resource code. Only the plan's `tags_all` shows them, so
> a required-tags policy has to run on the plan.
>
> Rego also lets me write **organisation-specific** rules no generic tool
> has, like "only a security group tagged `Exposure=internet-facing` may
> accept 0.0.0.0/0, and only on 80/443".

### Q2. A developer opens SSH to 0.0.0.0/0 and adds `#checkov:skip=CKV_AWS_24` to make CI green. What happens?

> The skip makes **Checkov** pass, but the PR is still blocked. My Rego
> policies run on the plan in the `terraform-plan` job and deny both
> `0.0.0.0/0` on a non-internet-facing group and port 22 from any source.
> `terraform-plan` is a **required** check, so the merge button stays
> disabled. A Checkov skip comment can't affect Rego; changing Rego means
> editing `policy/`.
>
> To stop skips being added quietly, I'd add `CODEOWNERS` so the security
> team must approve changes to `policy/`, `.checkov.yaml` and any new skip.

### Q3. The apply role has AdministratorAccess. What stops someone editing the workflow to use it without approval?

> The approval is enforced by **AWS**, not only by the workflow file. The
> apply role's **trust policy** only accepts an OIDC token whose `sub`
> claim ends in `:environment:production`. GitHub issues that claim only
> to a job running in the `production` environment, and that environment
> requires my approval before the job starts. A PR run gets a
> `:pull_request` claim instead, which the apply role rejects. So a
> modified workflow still can't assume the role.

### Q4. You hit two OIDC errors. What does each mean, and where do you look?

> **Both come from AWS STS**; GitHub only issues the token.
>
> - `The web identity token provided could not be validated`: AWS can't
>   verify the token at all. Check **IAM → Identity providers**: is the
>   GitHub OIDC provider there, with the right URL and audience? In my case
>   it didn't exist, because the stack had been destroyed.
> - `Not authorized to perform sts:AssumeRoleWithWebIdentity`: the token
>   is valid but the role refused it. Check that the **role exists** (my
>   deploy role didn't) and that its **trust policy's `sub` condition**
>   matches the repo/branch/environment. **CloudTrail** shows the exact
>   `sub` GitHub sent. That's how I once found GitHub's real claim format
>   (`repo:OWNER@ID/REPO@ID:...`).
>
> At assume-role time AWS checks the **trust policy** (who may assume the
> role), not the **permissions policy** (what the role may do), so adding
> actions to the role doesn't fix either error.

### Q5. The DB subnet has no internet route. Is allowing all egress on the DB security group harmless?

> No. "No internet route" isn't the same as "no way out". In my setup the
> DB route table had an **S3 gateway endpoint with no endpoint policy**.
> With open egress, a compromised host in that subnet could copy data to
> **any S3 bucket in the region, including an attacker's**, without
> touching the internet.
>
> I fixed it in depth: removed the S3 route from the DB route table, added
> an endpoint policy allowing only my buckets, and set the DB security
> group to **no egress**. Inbound it accepts only 3306 from the app tier's
> security group; replies still work because security groups are stateful.
>
> *If pushed back on "RDS is managed, who would compromise it?":* the
> route applies to **anything** placed in those subnets, not just RDS.
> Least privilege means not leaving a path nobody needs.

---

## Phase 2: Modules and state

### Q1. Why did you switch the subnets from `count` to `for_each`?

> With `count`, resources are identified by **position**: `[0]`, `[1]`.
> If I removed `us-east-1a` from the AZ list, `us-east-1b` would shift
> from `[1]` to `[0]`, and Terraform would destroy and re-create the
> subnet that should have stayed, along with everything in it. With
> `for_each` keyed by AZ (`["us-east-1b"]`), each subnet keeps its
> identity and only the removed AZ is touched.
>
> Rule of thumb: `count` for "N identical copies" or an on/off toggle;
> `for_each` whenever items have a natural identity.

### Q2. What would the plan show without `moved` blocks, and what would happen to the database?

> Terraform matches resources **by address**. It would see
> `aws_db_instance.this` in state but not in code, so it plans a
> **destroy**, and `module.database.aws_db_instance.this` in code but not
> in state, so it plans a **create**. For my full stack that's roughly
> "62 to add, 62 to destroy".
>
> Applied, the **database would be deleted and re-created empty**. With
> `skip_final_snapshot = true` that data is gone for good. There'd also be
> downtime and a new endpoint and password, and the apply would likely
> fail halfway when new IAM roles collide with old ones of the same name.
>
> `moved` blocks fix it **declaratively**: they're code, reviewed in the
> PR, and applied the same way to every copy of the state, unlike a
> manual `terraform state mv`. As a second safety net I added a policy
> (`policy/stateful_deletes.rego`) that fails any plan deleting or
> replacing a database or bucket unless it was approved in an earlier PR.

### Q3. Why one state file per environment?

> To limit the **blast radius**. With one shared state, a mistake in a dev
> change, a bad refactor or a corrupted state file hits **prod at the same
> time**. There are also practical reasons:
>
> - **Locking:** one state means one lock, so a dev plan blocks a prod hotfix.
> - **Access control:** state holds secrets in plaintext (my DB password),
>   so dev engineers shouldn't be able to read prod's state.
> - **Speed:** smaller states plan faster.
>
> I use one key per environment. At a bank I'd go further: a separate AWS
> account per environment, each with its own state bucket.

### Q4. How did you prove the refactor changed nothing? Is "0 to destroy" enough?

> Not on its own. I used three checks:
>
> 1. **Plan summary:** before and after were both `56 to add, 0 to
>    change, 0 to destroy`, plus `6 moved`.
> 2. **Coverage:** a script confirmed every one of the 62 old addresses
>    had a `moved` block.
> 3. **Value-by-value comparison** of the plan JSON before and after:
>    61 of 62 identical. The only difference was the DB port going from
>    "unknown, AWS default" to an explicit 3306, which is the same value.
>
> Why the summary isn't enough: most of the stack was destroyed at the
> time, so those resources were "to add" in **both** plans. An accidental
> change, like a wrong CIDR, would still show as "to add", not as a
> change. Only comparing the planned values catches it.

### Q5. During the refactor one of your policies silently stopped working. What happened?

> My S3 encryption policy only read the plan's **root module**. Once the
> buckets moved into `module.storage`, it stopped finding any buckets,
> so it had nothing to deny and **passed**. I proved it by removing a
> bucket's encryption config: still green. I fixed it to walk every module
> and added regression tests.
>
> The lesson: **policy as code fails open**. A rule that matches nothing
> looks exactly like a rule that found no problems. Policies need unit
> tests with realistic inputs, negative tests against real plans (inject
> a violation, expect a failure), and re-testing whenever the **code
> structure** changes, not only when the policies change. I hit the same
> class of bug in Phase 1, when a helper returned *undefined* instead of
> `false` and the SG policy skipped every non-ALB group.

---

## GCP foundation (set up early, used from Phase 3)

### Why did you need a domain and Cloud Identity just to use GCP?

> **Shared VPC only works inside an Organization**: host and service
> projects must belong to the same org. A plain Gmail account has no
> Organization; one only exists for a verified domain. So I bought a
> domain, verified it with a DNS TXT record, and signed up for **Cloud
> Identity Free**. That gave me the Org node at no cost, plus an
> org/folder/project hierarchy that mirrors how banks run GCP.

### What's the difference between a Cloud Identity Super Admin and a GCP IAM role?

> Super Admin controls the **identity** side: users, groups, the domain,
> 2-Step Verification. GCP permissions come from **IAM bindings** on the
> Org, folders and projects. They're separate systems: Google happened to
> grant my admin account Organization Administrator on first login, but
> that's an IAM binding, not part of being Super Admin. AWS has a similar
> split between the root user and IAM policies.

### How did you set up identities, and why?

> Two accounts. `admin@` is Super Admin and break-glass only, like the AWS
> root user, with 2-Step Verification enforced. `harry@` is the daily
> account, with **no** admin-console role and only the IAM roles it needs:
> Folder Admin, Organization Viewer, Project Creator, Billing Account
> Creator, Compute Shared VPC Admin, and Organization Policy Administrator.
>
> I deliberately did **not** give it Organization Administrator: that
> includes `setIamPolicy` on the Org, so it could grant itself anything.

### What is the `domain:` principal, and why did you remove its default grants?

> `domain:example.org` means **every user in the Cloud Identity domain**,
> now and in the future. On Org creation, Google grants it Project Creator
> and Billing Account Creator. That's implicit, ever-growing access: every
> new joiner or contractor could create projects outside the folder
> structure and open billing accounts, with no approval. I replaced it
> with explicit grants to my user, which is what Google's own setup
> checklist recommends. In production those grants would go to **groups**,
> so joiners and leavers are handled in one place.

### What's risky about Folder Admin?

> It includes `resourcemanager.folders.setIamPolicy`, so the holder can
> grant **any role** on any folder, and on every project under it,
> including to themselves. That's a **privilege escalation** path.
> Mitigations: IAM Deny policies, Privileged Access Manager for
> time-boxed approved elevation, group-based grants with access reviews,
> and alerting on `SetIamPolicy` in Cloud Audit Logs.

### What is keyless OIDC / Workload Identity Federation?

> Instead of storing a long-lived cloud key as a CI secret, the CI job
> gets a **signed, short-lived token** from GitHub describing exactly who
> it is (repo, branch, environment). The cloud verifies the signature and
> the claims against a trust policy, then issues **temporary credentials**
> (about an hour). There's nothing long-lived to leak or rotate, access is
> scoped per repo/branch/environment, and every exchange is in the audit
> log. AWS calls it OIDC federation (`AssumeRoleWithWebIdentity`); GCP
> calls it Workload Identity Federation. New GCP orgs even block service
> account key creation by default, so WIF is the expected path.

---

## Weak spots to review

These are the answers I didn't get right the first time:

- **Phase 1 Q2 (bypass via skip):** answered "I don't know". Remember the
  two independent layers and the required check.
- **Phase 1 Q4 (OIDC errors):** I thought one came from GitHub, and that
  the fix was adding actions to the role. Both come from AWS STS, and the
  fix is the OIDC provider or the **trust** policy.
- **Phase 1 Q5:** the instinct ("no") was right, but I missed my own
  evidence, the S3 endpoint exfiltration path, and over-restricted
  inbound ("nothing in").
- **Explaining the mechanism:** my first answers named the right idea but
  not *how* it works (trust policy vs permissions policy, plan vs code,
  required checks). Interviewers listen for the "how".
