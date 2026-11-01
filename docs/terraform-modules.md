# Terraform modules and environments

The infrastructure used to live in one flat `terraform/` folder with a
single state file. It's now split into **reusable modules** and a thin
**environment root** that wires them together, with its own state.

```
modules/                     reusable building blocks, no provider or backend config
  aws-network/               VPC, 3-tier subnets, route tables, IGW, VPC endpoints (no NAT)
  aws-storage/               receipts + deploy buckets
  aws-database/              RDS MySQL, DB security group, credentials in Secrets Manager
  aws-app/                   ALB, ASG (Spot/On-Demand, Graviton), launch template, app IAM role
  aws-github-oidc/           GitHub OIDC provider + ci / deploy / apply roles
envs/
  aws-dev/                   module calls + wiring, provider, backend, moved.tf, outputs
```

## In short

- **Module:** a folder of Terraform with inputs (variables) and outputs, called like a function. One module can be reused by many environments with different inputs.
- **Environment root:** the folder you run `terraform plan/apply` in. It owns the provider config, the backend (state location) and the wiring between modules, but no resources of its own.
- **`moved` block:** tells Terraform that a resource at an old address is the same object at a new address. Without it, moving `aws_vpc.this` into `module.network` would plan a destroy + create of the VPC.

**What I did**
- Split ~60 resources into 5 modules and an `aws-dev` environment, and filled in the outputs (app URL, DB address, bucket names, role ARNs).
- Wrote a `moved` block for every resource, including the subnets switching from `count` to `for_each`.
- Migrated the state to a per-environment key (`sa-portfolio/envs/aws-dev/terraform.tfstate`).
- **Proved zero infrastructure change** by comparing the plan JSON before and after, resource by resource.
- Found and fixed a policy gap the refactor created: the S3 encryption policy only looked at the root module, so it silently stopped checking every bucket once they moved into `module.storage`.

## Design decisions

| Decision | Why | Trade-off |
|---|---|---|
| Subnets use `for_each` keyed by AZ instead of `count` | With `count`, removing the first AZ shifts every index down by one, and Terraform destroys and re-creates the subnets in the AZs that stayed. With `for_each`, only the removed AZ is touched | Needed one `moved` block per subnet instance (`[0]` → `["us-east-1a"]`) |
| One state file per environment | A `dev` apply can never lock, read or corrupt another environment's state, and the blast radius of a bad apply is one environment | Cross-environment references need `terraform_remote_state` or data sources instead of direct references |
| State key kept under `sa-portfolio/` | The CI role's lock-file permission (`sa-portfolio/*`) still covers it, so no IAM change was needed | — |
| Modules have no `provider` or `backend` blocks | The caller decides region, credentials, default tags and where state lives, so the same module works in any account or environment | Each module still declares `required_providers` with a minimum version |
| S3 endpoint policy is built in the environment, not in `aws-network` | It names this environment's buckets. The network module takes the policy as an input instead of depending on the storage module | The environment's `main.tf` is a bit longer |
| Security groups live with the tier they protect (`db` SG in `aws-database`, `alb`/`app` SGs in `aws-app`) | Each module owns its own network boundary. The DB module only takes `allowed_security_group_ids` | `app` → `database` → `app` looks circular between modules. It isn't between resources (the DB SG needs the app SG; the app needs the secret ARN), and Terraform resolves dependencies per resource, not per module |
| Local module sources (`../../modules/...`) | Simple while there's one repo and one team | No independent versioning. With several teams, modules would move to their own repo and be pinned by git tag (`?ref=v1.2.0`), so a module change can't silently alter every environment |
| `moved` blocks kept after the refactor | Removing one before every copy of the state has been applied past the refactor turns that rename back into destroy + create | A long `moved.tf`; it can be deleted once no old state exists anywhere |

## Proof of zero infrastructure change

Done-when for this phase was *"`terraform plan` after the refactor shows
zero infrastructure changes"*. Three checks:

1. **Plan summary.** Before: `56 to add, 0 to change, 0 to destroy`. After: the same, plus `6 moved` (the only resources currently in state; the rest of the stack is destroyed between sessions).
2. **Coverage.** A script confirmed that every one of the 62 resource instances in the old plan maps to a `moved` block.
3. **Value-by-value comparison.** For each resource, the planned values before and after were compared through the `moved` mapping. **61 of 62 were identical.** The one difference is intended: `aws_db_instance.port` changed from "unknown" (AWS picks MySQL's default, 3306) to an explicit `3306`, because the module's `port` input now actually sets it. Same value, no infrastructure change.

Checkov reports the same results (0 failed, 26 skipped) and the same
checks per resource, apart from renamed addresses.

## State migration (done once)

```powershell
cd terraform;        terraform state pull > old-state.json   # old key
cd ../envs/aws-dev;  terraform init                         # new, empty key
terraform state push old-state.json
terraform plan                                               # "has moved to ..." only
```

The old state object (`sa-portfolio/terraform.tfstate`) is left in the
versioned bucket as a backup. Delete it once the new layout has been
applied at least once.

`terraform init -migrate-state` wasn't used, because it only migrates
within the *same* directory when the backend config changes. Here the root
directory changed too, so the state was pulled from the old root and
pushed into the new one.

## Adding another environment

1. Copy `envs/aws-dev` to `envs/aws-prod`.
2. Change the backend `key` to `sa-portfolio/envs/aws-prod/terraform.tfstate`.
3. Change the inputs (CIDRs, instance sizes, `project_name`) and delete `moved.tf`, since prod never had the old layout.
4. Account-wide resources (the GitHub OIDC provider exists once per account) would move to a shared `envs/global` root at that point. Today they sit in `aws-dev` because it's the only environment.
