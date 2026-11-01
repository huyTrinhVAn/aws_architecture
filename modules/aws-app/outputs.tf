output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "app_security_group_id" {
  description = "SG of the app instances -- grant it access to downstream tiers (e.g. the database)"
  value       = aws_security_group.app.id
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "asg_arn" {
  value = aws_autoscaling_group.app.arn
}
