# GitHub Actions -> GCP with no service account key anywhere (the Org
# blocks key creation anyway). Same model as the AWS OIDC roles:
#
#   GitHub job --OIDC token--> Workload Identity pool/provider (seed project)
#     --checks the token's claims--> impersonates a service account
#     --short-lived token (~1h)--> Terraform
#
# Two service accounts, mirroring the AWS roles:
#   tf-plan   read-only, usable by any job in this repo (PR plans)
#   tf-apply  can change shared/ and dev/, usable ONLY by a job running in
#             the "production" GitHub Environment, i.e. after approval
#
# Neither can touch the bootstrap/ folder: CI can never change its own
# identity or permissions. This file is applied locally by a human, like
# the AWS OIDC roles were.

locals {
  # Immutable numeric ID: renaming or transferring the repo, or someone
  # re-creating a repo with the same name, can't inherit this trust.
  github_repository_id = "1344911100"

  seed_project_id = google_project.this["seed"].project_id

  # Folders CI may manage. bootstrap/ is deliberately absent.
  ci_folders = {
    shared = google_folder.shared.name
    dev    = google_folder.dev.name
  }
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = local.seed_project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.this["seed/iam.googleapis.com"]]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  #checkov:skip=CKV_GCP_125:False positive -- the check only recognises an exact assertion.sub match; this gates on the immutable repository_id instead (stronger), plus per-account environment bindings

  project                            = local.seed_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  # Claims from GitHub's token, copied into attributes the IAM bindings
  # below can match on. Jobs without an environment get "none", so the
  # mapping never fails on a missing claim.
  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository_id" = "assertion.repository_id"
    "attribute.ref"           = "assertion.ref"
    "attribute.event_name"    = "assertion.event_name"
    "attribute.environment"   = "has(assertion.environment) ? assertion.environment : 'none'"
  }

  # Hard gate: tokens from any other repository are rejected outright,
  # before any IAM binding is even considered.
  attribute_condition = "assertion.repository_id == '${local.github_repository_id}'"
}

locals {
  wif_principal_set = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}"
}

# --- tf-plan: read-only --------------------------------------------------------

resource "google_service_account" "tf_plan" {
  project      = local.seed_project_id
  account_id   = "tf-plan"
  display_name = "Terraform plan (CI, read-only)"
}

# Any job in the repo, including PRs from branches. GitHub never issues an
# OIDC token to fork PRs, and this account can't change anything.
resource "google_service_account_iam_member" "tf_plan_wif" {
  service_account_id = google_service_account.tf_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.wif_principal_set}/attribute.repository_id/${local.github_repository_id}"
}

resource "google_folder_iam_member" "tf_plan_viewer" {
  #checkov:skip=CKV_GCP_116:Read-only and limited to the shared/ and dev/ folders; the per-service viewer-role alternative grows every phase -- revisit once the stack is complete

  for_each = local.ci_folders

  folder = each.value
  role   = "roles/viewer"
  member = google_service_account.tf_plan.member
}

# roles/viewer doesn't include reading IAM policies, which `plan` needs to
# refresh IAM bindings (e.g. the subnet's networkUser grant).
resource "google_folder_iam_member" "tf_plan_iam_reader" {
  for_each = local.ci_folders

  folder = each.value
  role   = "roles/iam.securityReviewer"
  member = google_service_account.tf_plan.member
}

# --- tf-apply: approval-gated ------------------------------------------------------

resource "google_service_account" "tf_apply" {
  project      = local.seed_project_id
  account_id   = "tf-apply"
  display_name = "Terraform apply (CI, approval-gated)"
}

# Only a job running in the "production" GitHub Environment -- which can't
# start until a required reviewer approves it -- carries
# environment=production in its token. A PR job, or a workflow edited to
# skip the environment, can't impersonate this account. Same gate as the
# AWS apply role's environment:production trust condition.
resource "google_service_account_iam_member" "tf_apply_wif" {
  service_account_id = google_service_account.tf_apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "${local.wif_principal_set}/attribute.environment/production"
}

# Owner on shared/ and dev/ only: Terraform creates networks, firewalls,
# VMs, Cloud SQL and IAM bindings inside those projects, so it needs broad
# rights -- the GCP equivalent of the AWS apply role's AdministratorAccess.
# The controls are around who can use it (approval + environment claim)
# and where (never the bootstrap folder holding this identity).
resource "google_folder_iam_member" "tf_apply_owner" {
  #checkov:skip=CKV_GCP_116:CI apply account must create networks, VMs, Cloud SQL and IAM bindings (like the AWS apply role's AdministratorAccess); scoped to shared/ and dev/, gated by environment approval
  #checkov:skip=CKV_GCP_44:Same as CKV_GCP_116 -- never granted on the bootstrap/ folder that holds this identity

  for_each = local.ci_folders

  folder = each.value
  role   = "roles/owner"
  member = google_service_account.tf_apply.member
}

# Shared VPC attaches a service project (dev/) to a host project (shared/),
# so the permission has to sit on a folder above both. Shared VPC Admin
# only enables hosts and attaches projects -- it grants nothing inside them.
resource "google_folder_iam_member" "tf_apply_xpn" {
  folder = google_folder.root.name
  role   = "roles/compute.xpnAdmin"
  member = google_service_account.tf_apply.member
}

# --- Terraform state access ----------------------------------------------------------

# Both accounts read every state file: envs/gcp-dev reads the bootstrap's
# outputs (project IDs) through terraform_remote_state.
resource "google_storage_bucket_iam_member" "tf_state_read" {
  for_each = {
    plan  = google_service_account.tf_plan.member
    apply = google_service_account.tf_apply.member
  }

  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectViewer"
  member = each.value
}

# plan writes nothing but the lock file: the condition limits write access
# to objects ending in .tflock, so this account can't alter any state.
resource "google_storage_bucket_iam_member" "tf_plan_lock" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectUser"
  member = google_service_account.tf_plan.member

  condition {
    title      = "terraform-lock-files-only"
    expression = "resource.name.endsWith('.tflock')"
  }
}

# apply writes state, but only under envs/: it can never overwrite the
# bootstrap state (and with it, this file's own resources).
resource "google_storage_bucket_iam_member" "tf_apply_state_write" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectUser"
  member = google_service_account.tf_apply.member

  condition {
    title      = "envs-state-only"
    expression = "resource.name.startsWith('projects/_/buckets/${google_storage_bucket.tfstate.name}/objects/envs/')"
  }
}
