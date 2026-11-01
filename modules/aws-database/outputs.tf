output "address" {
  description = "DB hostname (private, resolvable only inside the VPC)"
  value       = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "credentials_secret_arn" {
  description = "Secrets Manager secret holding host/port/username/password/dbname as JSON"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "security_group_id" {
  value = aws_security_group.db.id
}
