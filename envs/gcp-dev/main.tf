# The GCP dev environment. Project IDs come from gcp-bootstrap's state, not
# copy-pasted: the bootstrap owns the folders and projects, this root owns
# what runs inside them. Reading another root's outputs this way is how
# separate state files reference each other.

data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = "sa-tfstate-d463"
    prefix = "bootstrap"
  }
}

locals {
  host_project_id = data.terraform_remote_state.bootstrap.outputs.project_ids["host"]
  app_project_id  = data.terraform_remote_state.bootstrap.outputs.project_ids["app"]
}

data "google_project" "app" {
  project_id = local.app_project_id
}

module "network" {
  source = "../../modules/gcp-network"

  host_project_id     = local.host_project_id
  service_project_ids = [local.app_project_id]
  region              = var.region

  # The service project's Google APIs service agent creates managed
  # instance groups on the project's behalf, so it must be able to put VMs
  # in the shared subnet.
  app_subnet_users = [
    "serviceAccount:${data.google_project.app.number}@cloudservices.gserviceaccount.com",
  ]
}
