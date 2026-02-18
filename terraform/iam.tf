# IAM Role: github-actions-deploy
# Assumed by GitHub Actions via OIDC for all deployment operations

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/*:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = {
    Name = "github-actions-deploy"
  }
}

# Policy: S3 frontend deploy (existing buckets)
data "aws_iam_policy_document" "s3_frontend" {
  statement {
    sid    = "FrontendBucketAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = flatten([
      for bucket in values(local.frontend_buckets) : [
        "arn:aws:s3:::${bucket}",
        "arn:aws:s3:::${bucket}/*",
      ]
    ])
  }
}

resource "aws_iam_role_policy" "s3_frontend" {
  name   = "s3-frontend-deploy"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.s3_frontend.json
}

# Policy: CloudFront invalidation
data "aws_iam_policy_document" "cloudfront" {
  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudfront" {
  name   = "cloudfront-invalidation"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.cloudfront.json
}

# Policy: S3 deploy artifacts bucket
data "aws_iam_policy_document" "s3_artifacts" {
  statement {
    sid    = "ArtifactsBucketAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.deploy_artifacts.arn,
      "${aws_s3_bucket.deploy_artifacts.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_artifacts" {
  name   = "s3-deploy-artifacts"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.s3_artifacts.json
}

# Policy: S3 deploy metrics bucket
data "aws_iam_policy_document" "s3_metrics" {
  statement {
    sid    = "MetricsBucketWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.deploy_metrics.arn,
      "${aws_s3_bucket.deploy_metrics.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "s3_metrics" {
  name   = "s3-deploy-metrics"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.s3_metrics.json
}

# Policy: SSM SendCommand for API deploys
data "aws_iam_policy_document" "ssm" {
  statement {
    sid    = "SSMSendCommand"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
    ]
    resources = [
      "arn:aws:ssm:us-east-2:*:document/SonarMD-DeployAPI",
      "arn:aws:ec2:us-east-2:*:instance/*",
    ]
  }
}

resource "aws_iam_role_policy" "ssm" {
  name   = "ssm-deploy-api"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.ssm.json
}

# Policy: EC2 DescribeInstances (discover deploy targets)
data "aws_iam_policy_document" "ec2_describe" {
  statement {
    sid       = "EC2DescribeInstances"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ec2_describe" {
  name   = "ec2-describe-instances"
  role   = aws_iam_role.github_actions_deploy.id
  policy = data.aws_iam_policy_document.ec2_describe.json
}

# Output the role ARN for use in workflow configurations
output "deploy_role_arn" {
  description = "ARN of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions_deploy.arn
}
