output "instance_group" {
  description = "The MIG's instance group -- the load balancer's backend"
  value       = google_compute_region_instance_group_manager.app.instance_group
}

output "health_check_id" {
  value = google_compute_health_check.app.id
}

output "named_port" {
  value = "http"
}

output "service_account_email" {
  value = google_service_account.app.email
}
