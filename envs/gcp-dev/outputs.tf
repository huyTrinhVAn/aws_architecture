output "host_project_id" {
  value = local.host_project_id
}

output "app_project_id" {
  value = local.app_project_id
}

output "network_id" {
  value = module.network.network_id
}

output "app_subnet_self_link" {
  value = module.network.app_subnet_self_link
}
