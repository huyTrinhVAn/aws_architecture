variable "project_name" {
  description = "Short project name, used as a prefix for role names and tags"
  type        = string
}

variable "github_subject_prefix" {
  description = <<-EOT
    Start of the OIDC sub claim for the repo, e.g. "repo:OWNER@*/REPO@*".
    GitHub's actual claim includes immutable numeric IDs after the owner
    and repo names (repo:OWNER@OWNER_ID/REPO@REPO_ID:...), not just
    repo:OWNER/REPO:... as most docs show -- confirmed via CloudTrail's
    logged AccessDenied event. Wildcard the ID portions: pinning them would
    silently break if GitHub ever changed them, and each role is already
    scoped to one repo.
  EOT
  type        = string
}

variable "apply_environment" {
  description = "GitHub Environment (with a required reviewer) whose jobs may assume the apply role"
  type        = string
  default     = "production"
}

variable "state_lock_object_arn" {
  description = "S3 object ARN pattern of the Terraform state files -- the read-only CI role may write/delete only the .tflock objects next to them"
  type        = string
}

variable "deploy_bucket_arn" {
  description = "Bucket the deploy role uploads the app bundle to"
  type        = string
}

variable "deploy_asg_arn" {
  description = "Auto Scaling Group the deploy role may start an instance refresh on"
  type        = string
}
