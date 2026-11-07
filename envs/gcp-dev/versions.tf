terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }

  # Same bucket as gcp-bootstrap, its own prefix: one state per root.
  # The GCS backend locks the state automatically.
  backend "gcs" {
    bucket = "sa-tfstate-d463"
    prefix = "envs/gcp-dev"
  }
}

provider "google" {
  region = var.region

  default_labels = {
    project     = "sa-portfolio"
    environment = "dev"
    managed-by  = "terraform"
  }
}
