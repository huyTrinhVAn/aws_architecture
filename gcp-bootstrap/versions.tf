# GCP foundation: the folder hierarchy, the three projects and the GCS
# bucket that holds every other GCP root's Terraform state.
#
# Same chicken-and-egg as terraform-bootstrap/ on AWS: the state bucket
# can't hold the state of the config that creates it before it exists. So
# the first apply used local state, then `terraform init -migrate-state`
# moved it into the bucket it had just created -- unlike the AWS
# bootstrap, whose state stays on one laptop.
#
# Rebuilding from scratch (new org/account): comment out the backend
# block, apply with local state, put the new bucket name below, and run
# `terraform init -migrate-state` again.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # The GCS backend locks the state automatically (a .tflock object next
  # to it) -- no extra setting needed, unlike use_lockfile on S3.
  backend "gcs" {
    bucket = "sa-tfstate-d463"
    prefix = "bootstrap"
  }
}

provider "google" {
  region = var.region

  # Labels are GCP's equivalent of AWS tags (lowercase keys and values).
  default_labels = {
    project    = "sa-portfolio"
    managed-by = "terraform"
  }
}
