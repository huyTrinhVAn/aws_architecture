# Resource hierarchy:
#
#   Organization
#   └── sa-portfolio/                    folder: everything for this project
#       ├── bootstrap/  -> seed project  Terraform state, later the CI identity
#       ├── shared/     -> host project  Shared VPC: network, firewall, NAT, DNS
#       └── dev/        -> app project   Shared VPC service project: VMs, LB, Cloud SQL
#
# IAM bindings and org policies set on a folder are inherited by every
# project under it -- the GCP equivalent of AWS Organizations OUs + SCPs.
# A future prod/ folder gets stricter policies without touching dev/.

# Project IDs are globally unique across all of GCP and can never be
# reused, even after deletion -- a random suffix avoids collisions.
resource "random_id" "suffix" {
  byte_length = 2
}

locals {
  suffix = random_id.suffix.hex
}

# --- Folders -------------------------------------------------------------------

resource "google_folder" "root" {
  display_name = "sa-portfolio"
  parent       = "organizations/${var.org_id}"

  # Folders can't be deleted while they contain projects, and a deleted
  # folder blocks reusing its name for 30 days.
  deletion_protection = false
}

resource "google_folder" "bootstrap" {
  display_name        = "bootstrap"
  parent              = google_folder.root.name
  deletion_protection = false
}

resource "google_folder" "shared" {
  display_name        = "shared"
  parent              = google_folder.root.name
  deletion_protection = false
}

resource "google_folder" "dev" {
  display_name        = "dev"
  parent              = google_folder.root.name
  deletion_protection = false
}

# --- Projects ------------------------------------------------------------------

locals {
  projects = {
    seed = {
      name   = "${var.name_prefix}-seed"
      folder = google_folder.bootstrap.name
      apis = [
        "storage.googleapis.com",        # the state bucket
        "iam.googleapis.com",            # service accounts (Phase 3.8)
        "iamcredentials.googleapis.com", # short-lived SA tokens for WIF
        "sts.googleapis.com",            # token exchange for WIF
        "cloudresourcemanager.googleapis.com",
        "serviceusage.googleapis.com",
        "cloudbilling.googleapis.com",
      ]
    }
    host = {
      name   = "${var.name_prefix}-net-host"
      folder = google_folder.shared.name
      apis = [
        "compute.googleapis.com",           # VPC, subnets, firewall, Cloud NAT
        "dns.googleapis.com",               # Cloud DNS private zone
        "servicenetworking.googleapis.com", # private IP for Cloud SQL
      ]
    }
    app = {
      name   = "${var.name_prefix}-dev-app"
      folder = google_folder.dev.name
      apis = [
        "compute.googleapis.com", # VMs, load balancer, Cloud Armor
        "sqladmin.googleapis.com",
        "secretmanager.googleapis.com",
        "servicenetworking.googleapis.com",
      ]
    }
  }

  # Flattened to one entry per (project, API) so each API is its own
  # resource -- adding one API later doesn't touch the others.
  project_apis = merge([
    for key, project in local.projects : {
      for api in project.apis : "${key}/${api}" => {
        project = key
        api     = api
      }
    }
  ]...)
}

resource "google_project" "this" {
  #checkov:skip=CKV2_GCP_5:Admin Activity audit logs are always on; Data Access logs (billed by volume) are configured once at Org level in roadmap Phase 5

  for_each = local.projects

  name            = each.value.name
  project_id      = "${each.value.name}-${local.suffix}"
  folder_id       = each.value.folder
  billing_account = var.billing_account

  # New projects get a "default" VPC with permissive firewall rules (SSH
  # and RDP open to 0.0.0.0/0) unless told otherwise. All networking is
  # created explicitly, in the host project only.
  auto_create_network = false

  # The provider refuses to delete projects unless this says otherwise.
  # Only the seed project (holding every GCP state file) keeps that
  # protection; host/app are lab projects torn down between sessions.
  deletion_policy = each.key == "seed" ? "PREVENT" : "DELETE"
}

resource "google_project_service" "this" {
  for_each = local.project_apis

  project = google_project.this[each.value.project].project_id
  service = each.value.api

  # Leave the API enabled if this resource is removed: disabling an API
  # can break whatever still depends on it in the project.
  disable_on_destroy = false
}

# --- Terraform state bucket -----------------------------------------------------

resource "google_storage_bucket" "tfstate" {
  #checkov:skip=CKV_GCP_62:Access logs need a separate log bucket; deferred to roadmap Phase 5 (observability), like the S3 access logs on AWS

  name     = "${var.name_prefix}-tfstate-${local.suffix}"
  project  = google_project.this["seed"].project_id
  location = var.region

  # Required anyway by the org policy storage.uniformBucketLevelAccess:
  # access is IAM-only, no per-object ACLs.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Every state write keeps the previous version, so a corrupted or bad
  # state can be rolled back. A non-current version is deleted only once
  # it's both 30+ days old and has 5 newer versions (conditions are ANDed),
  # so a rarely-changed state never loses its last good copies.
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions         = 5
      days_since_noncurrent_time = 30
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.this["seed/storage.googleapis.com"]]

  # Holds the state of every GCP root -- losing it is far worse than having
  # to remove this block by hand if it's ever genuinely needed.
  lifecycle {
    prevent_destroy = true
  }
}
