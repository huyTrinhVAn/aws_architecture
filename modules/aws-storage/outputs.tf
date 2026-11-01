output "receipts_bucket_name" {
  value = aws_s3_bucket.receipts.bucket
}

output "receipts_bucket_arn" {
  value = aws_s3_bucket.receipts.arn
}

output "deploy_bucket_name" {
  value = aws_s3_bucket.deploy.bucket
}

output "deploy_bucket_arn" {
  value = aws_s3_bucket.deploy.arn
}
