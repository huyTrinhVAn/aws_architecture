# Subnet outputs are lists in var.azs order, so callers that spread
# something across AZs (ALB, ASG, DB subnet group) don't depend on map keys.

output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = [for az in var.azs : aws_subnet.public[az].id]
}

output "app_subnet_ids" {
  value = [for az in var.azs : aws_subnet.app[az].id]
}

output "db_subnet_ids" {
  value = [for az in var.azs : aws_subnet.db[az].id]
}

output "app_subnet_cidrs" {
  value = [for az in var.azs : aws_subnet.app[az].cidr_block]
}

output "db_subnet_cidrs" {
  value = [for az in var.azs : aws_subnet.db[az].cidr_block]
}

output "vpc_endpoints_security_group_id" {
  description = "SG on the interface endpoint ENIs -- allow egress to it on 443 to reach SSM/Secrets Manager"
  value       = aws_security_group.vpc_endpoints.id
}

output "s3_prefix_list_id" {
  description = "S3's regional IP ranges -- allow egress to it on 443 to reach S3 through the gateway endpoint"
  value       = aws_vpc_endpoint.s3.prefix_list_id
}
