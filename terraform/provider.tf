provider "aws" {
  region = var.aws_region

  # Stamped onto every taggable resource this provider creates, so the
  # required-tags policy (policy/tags.rego) can't be failed by a resource
  # someone forgot to tag by hand. Per-resource tags (Name, Tier...) are
  # merged on top of these.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
