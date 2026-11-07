# org_id and billing_account come from terraform.tfvars, which is
# gitignored -- see terraform.tfvars.example. Neither is a secret, but a
# billing account ID is what lets anyone with the right role run up
# charges, so it stays out of the repo.

variable "org_id" {
  description = "Numeric ID of the GCP Organization (gcloud organizations list)"
  type        = string
}

variable "billing_account" {
  description = "Billing account the projects are charged to, e.g. 012345-ABCDEF-678901 (gcloud billing accounts list)"
  type        = string
}

variable "region" {
  description = "Default region for regional resources (the state bucket, later the subnets)"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for folder names and project IDs"
  type        = string
  default     = "sa"
}
