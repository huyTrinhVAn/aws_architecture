# Bootstrap config: creates the S3 bucket that holds the *main* project's
# Terraform state. This config's own state stays local on purpose -- you
# can't store a backend's state inside the backend it's creating (the
# classic chicken-and-egg problem). It's applied once, rarely touched again.

terraform {
  required_version = ">= 1.10" # need 1.10+ for S3 native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "sa-portfolio-tfstate-${random_id.suffix.hex}"

  # Refuse `terraform destroy` on this bucket -- it holds the state for
  # every other resource in the project; losing it is far worse than the
  # inconvenience of removing this lifecycle block by hand if it's ever
  # genuinely needed.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "sa-portfolio-tfstate"
    Project = "sa-portfolio"
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled" # lets a corrupted/bad state write be rolled back
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

output "bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}
