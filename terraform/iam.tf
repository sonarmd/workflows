# IAM Role: github-actions-deploy
# Assumed by GitHub Actions via OIDC for CI/CD deployments

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_actions_deploy" {
  name = "github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/*:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "github-actions-deploy"
  }
}

# ── S3 Frontend Deploy Policy ──

resource "aws_iam_role_policy" "s3_frontend_deploy" {
  name = "s3-frontend-deploy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3FrontendBuckets"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = flatten([
          for bucket in local.frontend_buckets : [
            "arn:aws:s3:::${bucket}",
            "arn:aws:s3:::${bucket}/*"
          ]
        ])
      }
    ]
  })
}

locals {
  frontend_buckets = [
    # Dev
    "admin.dev.sonarmd.com",
    "my.dev.sonarmd.com",
    "care.dev.sonarmd.com",
    "seat.dev.sonarmd.com",
    # Staging
    "admin.stg.sonarmd.com",
    "my.stg.sonarmd.com",
    "care.stg.sonarmd.com",
    "seat.stg.sonarmd.com",
    # Production
    "admin.sonarmd.com",
    "my.sonarmd.com",
    "care.sonarmd.com",
    "seat.sonarmd.com",
  ]
}

# ── CloudFront Invalidation Policy ──

resource "aws_iam_role_policy" "cloudfront_invalidation" {
  name = "cloudfront-invalidation"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation"
        ]
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
      }
    ]
  })
}

# ── S3 Deploy Artifacts Policy ──

resource "aws_iam_role_policy" "s3_deploy_artifacts" {
  name = "s3-deploy-artifacts"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DeployArtifacts"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deploy_artifacts.arn,
          "${aws_s3_bucket.deploy_artifacts.arn}/*"
        ]
      }
    ]
  })
}

# ── S3 Deploy Metrics Policy ──

resource "aws_iam_role_policy" "s3_deploy_metrics" {
  name = "s3-deploy-metrics"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DeployMetrics"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deploy_metrics.arn,
          "${aws_s3_bucket.deploy_metrics.arn}/*"
        ]
      }
    ]
  })
}

# ── SSM Run Command Policy ──

resource "aws_iam_role_policy" "ssm_deploy" {
  name = "ssm-deploy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMSendCommand"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:document/${aws_ssm_document.deploy_api.name}",
          "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/*"
        ]
      },
      {
        Sid    = "SSMGetCommandStatus"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── EC2 Describe Policy ──

resource "aws_iam_role_policy" "ec2_describe" {
  name = "ec2-describe"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── Output ──

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions_deploy.arn
}
