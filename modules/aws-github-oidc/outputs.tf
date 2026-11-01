output "ci_role_arn" {
  value = aws_iam_role.ci.arn
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}
