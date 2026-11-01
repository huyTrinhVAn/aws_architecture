output "vpc_id" {
  value = module.network.vpc_id
}

output "app_url" {
  description = "Public entry point (HTTP until the HTTPS listener lands)"
  value       = "http://${module.app.alb_dns_name}"
}

output "asg_name" {
  value = module.app.asg_name
}

output "db_address" {
  description = "Private DB hostname; credentials are in the db_credentials secret, never in outputs"
  value       = module.database.address
}

output "db_credentials_secret_arn" {
  value = module.database.credentials_secret_arn
}

output "receipts_bucket_name" {
  value = module.storage.receipts_bucket_name
}

output "deploy_bucket_name" {
  value = module.storage.deploy_bucket_name
}

output "github_actions_role_arn" {
  value = module.github_oidc.ci_role_arn
}

output "github_actions_deploy_role_arn" {
  value = module.github_oidc.deploy_role_arn
}

output "github_actions_apply_role_arn" {
  value = module.github_oidc.apply_role_arn
}
