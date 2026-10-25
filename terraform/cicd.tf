# Lets GitHub Actions assume an AWS role via OIDC federation instead of
# storing a long-lived access key/secret as a GitHub secret -- AWS issues
# short-lived credentials per workflow run, and there's nothing standing
# to leak if the repo is ever compromised.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  tags = {
    Name    = "${var.project_name}-github-oidc"
    Project = var.project_name
  }
}

# Scoped to this exact repo: runs on main, plus pull_request runs so every
# PR gets a plan to review. Safe to open to PRs because the role is
# read-only, and GitHub never issues an OIDC token to a pull_request run
# triggered from a fork -- only branches pushed to this repo get one.
resource "aws_iam_role" "github_actions_ci" {
  name = "${var.project_name}-github-actions-ci"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # GitHub's actual sub claim includes immutable numeric IDs after
          # the owner and repo names (repo:OWNER@OWNER_ID/REPO@REPO_ID:...),
          # not just repo:OWNER/REPO:... as most docs/examples show --
          # confirmed via CloudTrail's logged AccessDenied event. Wildcard
          # the ID portions since they add no security value here (this
          # role is already scoped to one specific role ARN) and pinning
          # them would silently break if GitHub ever changes the ID.
          "token.actions.githubusercontent.com:sub" = [
            "repo:huyTrinhVAn@*/aws_architecture@*:ref:refs/heads/main",
            "repo:huyTrinhVAn@*/aws_architecture@*:pull_request",
          ]
        }
      }
    }]
  })

  tags = {
    Name    = "${var.project_name}-github-actions-ci"
    Project = var.project_name
  }
}

# Read-only is sufficient for `terraform plan` (it only describes existing
# resources to compute a diff) -- this role is deliberately not granted
# anything that could mutate the account. `apply` uses the separate,
# approval-gated github_actions_apply role below.
resource "aws_iam_role_policy_attachment" "github_actions_ci_readonly" {
  role       = aws_iam_role.github_actions_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess covers reading the state file itself, but `terraform plan`
# with S3 native locking also needs to write and then delete a small
# `.tflock` object to acquire/release the lock before it can read state --
# a write action ReadOnlyAccess deliberately excludes. Scoped to exactly
# the state file's path in this one bucket, not broad S3 write access.
resource "aws_iam_role_policy" "github_actions_ci_state_lock" {
  name = "${var.project_name}-github-actions-ci-state-lock"
  role = aws_iam_role.github_actions_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StateLockFile"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = "arn:aws:s3:::sa-portfolio-tfstate-42ac9a0e/sa-portfolio/*"
    }]
  })
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_ci.arn
}

# Separate from github_actions_ci on purpose -- that role stays read-only
# for `terraform plan`. This role exists only to let the app-bundle build
# job upload to the deploy bucket, so a bug or compromise in that one
# workflow step can't be leveraged into reading the rest of the account.
resource "aws_iam_role" "github_actions_deploy" {
  name = "${var.project_name}-github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:huyTrinhVAn@*/aws_architecture@*:ref:refs/heads/main"
        }
      }
    }]
  })

  tags = {
    Name    = "${var.project_name}-github-actions-deploy"
    Project = var.project_name
  }
}

# Only PutObject on the deploy bucket -- no read, no delete, no access to
# any other bucket or service. This role cannot read receipts, cannot touch
# Terraform state, cannot see any other resource in the account.
resource "aws_iam_role_policy" "github_actions_deploy_s3" {
  name = "${var.project_name}-github-actions-deploy-s3"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "UploadAppBundle"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.deploy.arn}/*"
    }]
  })
}

# Instances only fetch the bundle at boot (user_data), so uploading a new
# one changes nothing until they're replaced. An instance refresh replaces
# them one at a time behind the ALB -- a rolling deploy with no downtime.
# Scoped to this one ASG; the role still can't launch, terminate or
# resize anything directly.
resource "aws_iam_role_policy" "github_actions_deploy_refresh" {
  name = "${var.project_name}-github-actions-deploy-refresh"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RollOutNewBundle"
      Effect   = "Allow"
      Action   = ["autoscaling:StartInstanceRefresh"]
      Resource = aws_autoscaling_group.app.arn
    }]
  })
}

output "github_actions_deploy_role_arn" {
  value = aws_iam_role.github_actions_deploy.arn
}

# `terraform apply` from CI. The trust policy matches ONLY the
# `environment:production` sub claim, which GitHub issues only to a job
# that declares `environment: production` -- and that job can't start
# until a required reviewer approves it in the GitHub UI. So the approval
# gate is enforced by AWS, not just by the workflow file: a modified
# workflow that skips the environment simply can't assume this role.
resource "aws_iam_role" "github_actions_apply" {
  name = "${var.project_name}-github-actions-apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:huyTrinhVAn@*/aws_architecture@*:environment:production"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-github-actions-apply"
  }
}

# Terraform here manages IAM roles, VPCs, RDS, ALBs... so apply genuinely
# needs near-admin rights. The controls are around *who can use* the role
# (trust policy + environment approval above), not inside it. Next step
# for a production setup: a permissions boundary that blocks IAM changes
# outside the project's own role names.
resource "aws_iam_role_policy_attachment" "github_actions_apply_admin" {
  #checkov:skip=CKV_AWS_274:Apply role must create IAM/VPC/RDS resources; access is gated by the environment-scoped trust policy + manual approval

  role       = aws_iam_role.github_actions_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_actions_apply_role_arn" {
  value = aws_iam_role.github_actions_apply.arn
}
