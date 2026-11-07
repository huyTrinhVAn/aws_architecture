output "network_id" {
  value = google_compute_network.this.id
}

output "network_self_link" {
  description = "Needed by Cloud SQL's private_network setting"
  value       = google_compute_network.this.self_link
}

output "app_subnet_self_link" {
  description = "Subnet the service projects place their VMs in"
  value       = google_compute_subnetwork.app.self_link
}

output "app_subnet_cidr" {
  value = google_compute_subnetwork.app.ip_cidr_range
}

output "private_services_connection" {
  description = "Depend on this before creating a Cloud SQL instance with a private IP"
  value       = google_service_networking_connection.private_services.id
}
