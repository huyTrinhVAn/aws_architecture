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

# Scoped to this exact repo AND branch -- a workflow run on a fork, a PR
# branch, or any other repo cannot assume this role, only a run whose
# checked-out ref is refs/heads/main on huyTrinhVAn/aws_architecture.
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
          "token.actions.githubusercontent.com:sub" = "repo:huyTrinhVAn@*/aws_architecture@*:ref:refs/heads/main"
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
# resources to compute a diff) -- CI is deliberately not granted anything
# that could mutate the account. `apply` stays a manual, local action.
resource "aws_iam_role_policy_attachment" "github_actions_ci_readonly" {
  role       = aws_iam_role.github_actions_ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_ci.arn
}
