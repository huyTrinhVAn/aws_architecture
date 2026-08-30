# Phase 5: two S3 buckets kept separate on purpose -- receipts (business
# data, needs versioning + a lifecycle strategy) and deploy artifacts (the
# app bundle, needs neither) get different IAM permissions on the app role,
# which would be muddier if they shared one bucket.

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --- Receipts bucket ---------------------------------------------------------

resource "aws_s3_bucket" "receipts" {
  bucket = "${var.project_name}-receipts-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-receipts"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "receipts" {
  bucket                  = aws_s3_bucket.receipts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "receipts" {
  bucket = aws_s3_bucket.receipts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "receipts" {
  bucket = aws_s3_bucket.receipts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "receipts" {
  bucket = aws_s3_bucket.receipts.id

  rule {
    id     = "tiered-storage"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# --- Deploy artifacts bucket --------------------------------------------------
# Holds the app deployment bundle (see Phase 5 notes on getting Flask onto
# an instance with no internet access). No versioning/lifecycle needed --
# only the latest bundle matters, and it's small.

resource "aws_s3_bucket" "deploy" {
  bucket = "${var.project_name}-deploy-${random_id.bucket_suffix.hex}"

  tags = {
    Name    = "${var.project_name}-deploy"
    Project = var.project_name
  }
}

resource "aws_s3_bucket_public_access_block" "deploy" {
  bucket                  = aws_s3_bucket.deploy.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
