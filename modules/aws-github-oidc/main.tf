# Lets GitHub Actions assume AWS roles via OIDC federation instead of
# storing a long-lived access key/secret as a GitHub secret -- AWS issues
# short-lived credentials per workflow run, and there's nothing standing
# to leak if the repo is ever compromised.
#
# Three roles, one per job type, each trusting only the sub claims of the
# runs that need it:
#   ci     -- read-only `terraform plan`, on main and on PRs
#   deploy -- upload the app bundle + roll it out, main only
#   apply  -- `terraform apply`, only from the approval-gated environment

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

# --- ci: read-only plan -------------------------------------------------------

# Runs on main, plus pull_request runs so every PR gets a plan to review.
# Safe to open to PRs because the role is read-only, and GitHub never
# issues an OIDC token to a pull_request run triggered from a fork -- only
# branches pushed to this repo get one.
resource "aws_iam_role" "ci" {
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
          "token.actions.githubusercontent.com:sub" = [
            "${var.github_subject_prefix}:ref:refs/heads/main",
            "${var.github_subject_prefix}:pull_request",
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
# anything that could mutate the account.
resource "aws_iam_role_policy_attachment" "ci_readonly" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ReadOnlyAccess covers reading the state file itself, but `terraform plan`
# with S3 native locking also needs to write and then delete a small
# `.tflock` object to acquire/release the lock before it can read state --
# a write action ReadOnlyAccess deliberately excludes. Scoped to the state
# files' path in the one state bucket, not broad S3 write access.
resource "aws_iam_role_policy" "ci_state_lock" {
  name = "${var.project_name}-github-actions-ci-state-lock"
  role = aws_iam_role.ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StateLockFile"
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Resource = var.state_lock_object_arn
    }]
  })
}

# --- deploy: app bundle upload + rollout ------------------------------------

# Separate from ci on purpose -- that role stays read-only for `terraform
# plan`. This role exists only to let the app-bundle job upload to the
# deploy bucket and roll it out, so a bug or compromise in that one
# workflow step can't be leveraged into reading the rest of the account.
resource "aws_iam_role" "deploy" {
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
          "token.actions.githubusercontent.com:sub" = "${var.github_subject_prefix}:ref:refs/heads/main"
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
resource "aws_iam_role_policy" "deploy_s3" {
  name = "${var.project_name}-github-actions-deploy-s3"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "UploadAppBundle"
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${var.deploy_bucket_arn}/*"
    }]
  })
}

# Instances only fetch the bundle at boot (user_data), so uploading a new
# one changes nothing until they're replaced. An instance refresh replaces
# them one at a time behind the ALB -- a rolling deploy with no downtime.
# Scoped to this one ASG; the role still can't launch, terminate or
# resize anything directly.
resource "aws_iam_role_policy" "deploy_refresh" {
  name = "${var.project_name}-github-actions-deploy-refresh"
  role = aws_iam_role.deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "RollOutNewBundle"
      Effect   = "Allow"
      Action   = ["autoscaling:StartInstanceRefresh"]
      Resource = var.deploy_asg_arn
    }]
  })
}

# --- apply: approval-gated terraform apply ----------------------------------

# The trust policy matches ONLY the `environment:<apply_environment>` sub
# claim, which GitHub issues only to a job that declares that environment
# -- and that job can't start until a required reviewer approves it in
# the GitHub UI. So the approval gate is enforced by AWS, not just by the
# workflow file: a modified workflow that skips the environment simply
# can't assume this role.
resource "aws_iam_role" "apply" {
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
          "token.actions.githubusercontent.com:sub" = "${var.github_subject_prefix}:environment:${var.apply_environment}"
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
resource "aws_iam_role_policy_attachment" "apply_admin" {
  #checkov:skip=CKV_AWS_274:Apply role must create IAM/VPC/RDS resources; access is gated by the environment-scoped trust policy + manual approval

  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
