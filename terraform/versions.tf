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

  backend "s3" {
    bucket       = "sa-portfolio-tfstate-42ac9a0e"
    key          = "sa-portfolio/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
