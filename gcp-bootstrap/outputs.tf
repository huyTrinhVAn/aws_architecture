output "folder_ids" {
  value = {
    root      = google_folder.root.folder_id
    bootstrap = google_folder.bootstrap.folder_id
    shared    = google_folder.shared.folder_id
    dev       = google_folder.dev.folder_id
  }
}

output "project_ids" {
  description = "seed = state + CI identity, host = Shared VPC host, app = dev service project"
  value = {
    for key, project in google_project.this : key => project.project_id
  }
}

output "tfstate_bucket" {
  description = "GCS bucket for every other GCP root's backend \"gcs\" block"
  value       = google_storage_bucket.tfstate.name
}
