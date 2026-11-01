# Phase 5: two S3 buckets kept separate on purpose -- receipts (business
# data, needs versioning + a lifecycle strategy) and deploy artifacts (the
# app bundle, needs neither) get different IAM permissions on the app role,
# which would be muddier if they shared one bucket.

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --- Receipts bucket ---------------------------------------------------------

resource "aws_s3_bucket" "receipts" {
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is enough for lab data; SSE-KMS with a customer-managed key adds per-request KMS cost
  #checkov:skip=CKV_AWS_18:Server access logs need a separate log bucket; deferred to roadmap Phase 5 (observability)
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles storage cost; single-region lab
  #checkov:skip=CKV2_AWS_62:No consumer for S3 event notifications exists -- nothing to notify

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

    # A failed multipart upload (e.g. a receipt upload interrupted
    # mid-way) leaves invisible parts behind that are billed forever.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# --- Deploy artifacts bucket --------------------------------------------------
# Holds the app deployment bundle (see Phase 5 notes on getting Flask onto
# an instance with no internet access). No versioning or storage tiering
# needed -- only the latest bundle matters, and it's small.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "deploy" {
  #checkov:skip=CKV_AWS_21:Only the latest bundle matters and CI rebuilds it on every push to main -- versioning would only keep stale copies
  #checkov:skip=CKV_AWS_145:SSE-S3 (AES256) is enough for a build artifact with no business data
  #checkov:skip=CKV_AWS_18:Server access logs need a separate log bucket; deferred to roadmap Phase 5 (observability)
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles storage cost; single-region lab
  #checkov:skip=CKV2_AWS_62:No consumer for S3 event notifications exists -- nothing to notify

  # Named after the account ID rather than the random suffix the receipts
  # bucket uses: CI has to know this name to upload the bundle, and a
  # random suffix changed every time the stack was destroyed and
  # re-created, silently breaking the hard-coded name in the workflow.
  # Account IDs are unique, so the name is still globally unique.
  bucket = "${var.project_name}-deploy-${data.aws_caller_identity.current.account_id}"

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

# The bundle upload from CI is a single PUT today, but a growing bundle
# switches the AWS CLI to multipart -- same orphaned-parts cost as above.
resource "aws_s3_bucket_lifecycle_configuration" "deploy" {
  bucket = aws_s3_bucket.deploy.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}
