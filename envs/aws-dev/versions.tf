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

  # One state file per environment: an apply in dev can never lock, read
  # or corrupt another environment's state. The key stays under
  # sa-portfolio/ so the CI role's lock-file permission (state_lock_object_arn
  # below) still covers it.
  backend "s3" {
    bucket       = "sa-portfolio-tfstate-42ac9a0e"
    key          = "sa-portfolio/envs/aws-dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
