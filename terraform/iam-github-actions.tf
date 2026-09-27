# ==========================================
# GITHUB ACTIONS OIDC — CI role for the ci.yml workflow
# ==========================================
# Replaces static AWS access keys (aws-access-key-id/aws-secret-access-key
# in ci.yml, currently read from GitHub secrets) with a short-lived,
# federated role assumed via OIDC. No long-lived AWS credentials sit in
# GitHub secrets with this approach.
#
# IMPORTANT — GitHub's immutable subject claims (rolled out for
# repositories created/renamed after 2026-07-15): the OIDC token's `sub`
# claim may be "repo:<owner>@<ownerId>/<repo>@<repoId>:ref:refs/heads/main"
# instead of the plain "repo:<owner>/<repo>:ref:refs/heads/main" format.
# Using the plain format when the immutable format is actually in effect
# causes AssumeRoleWithWebIdentity to fail with a generic AccessDenied,
# even though everything else about the trust policy is correct — this
# happened on the sibling devops-microservices-crewAi repo and cost real
# debugging time. Get the REAL value before trusting the placeholder below:
#
#   1. Try to assume the role once (it will fail with the placeholder).
#   2. Pull the real subject from CloudTrail:
#        aws cloudtrail lookup-events \
#          --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
#          --max-results 5 --region us-east-1 \
#          --query 'Events[0].CloudTrailEvent'
#      Look at userIdentity.principalId / userName in the decoded event —
#      that is the exact literal `sub` string GitHub actually sent.
#   3. Put that exact string into var.github_actions_oidc_subjects below
#      (via -var or a .tfvars file), then re-apply.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "github-actions-oidc-provider"
  }
}

variable "github_actions_oidc_subjects" {
  description = <<-EOT
    Exact OIDC "sub" claim values this role trusts, for the StringLike
    condition. Start with the plain-name placeholder below, but VERIFY
    against a real CloudTrail AssumeRoleWithWebIdentity event (see the
    comment above this variable in iam-github-actions.tf) — if this repo
    is subject to GitHub's immutable subject claims, the placeholder will
    NOT match the real token and every workflow run will fail with
    AccessDenied on sts:AssumeRoleWithWebIdentity.
  EOT
  type    = list(string)
  default = [
    "repo:<your-github-owner>/devops-100microservices:ref:refs/heads/main",
    "repo:<your-github-owner>/devops-100microservices:ref:refs/heads/develop",
  ]
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = var.github_actions_oidc_subjects
    }
  }
}

resource "aws_iam_role" "github_actions_ci" {
  name               = "${var.project_name}-github-actions-ci-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = {
    Name    = "${var.project_name}-github-actions-ci-role"
    Purpose = "CI build/push to ECR and GitOps commit for ci.yml"
  }
}

# ECR push scoped to this project's repositories. Adjust the resource list
# if ECR repo names differ from the apps/ directory names.
data "aws_iam_policy_document" "ecr_push" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # account-wide by AWS design, no resource-level scoping exists
  }

  statement {
    sid = "ECRPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:BatchGetImage",
      "ecr:DescribeRepositories",
      "ecr:CreateRepository",
    ]
    resources = ["arn:aws:ecr:*:*:repository/*"]
  }
}

resource "aws_iam_role_policy" "github_actions_ci_ecr" {
  name   = "ecr-push"
  role   = aws_iam_role.github_actions_ci.id
  policy = data.aws_iam_policy_document.ecr_push.json
}

output "github_actions_ci_role_arn" {
  description = "IAM role ARN for ci.yml — use as AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions_ci.arn
}
