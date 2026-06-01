# IAM Role: github-actions-deploy
# Assumed by GitHub Actions via OIDC for CI/CD deployments
# Trust is restricted to specific sonarmd repos only

data "aws_caller_identity" "current" {}

variable "allowed_repos" {
  description = "GitHub repos allowed to assume the deploy role (OIDC subject claim)"
  type        = list(string)
  default = [
    "repo:sonarmd/frontend:*",
    "repo:sonarmd/triggr_api:*",
    "repo:sonarmd/frontend-patient-app:*",
    "repo:sonarmd/triggr_misc:*",
    "repo:sonarmd/workflows:*",
  ]
}

resource "aws_iam_role" "github_actions_deploy" {
  name                 = "github-actions-deploy"
  max_session_duration = 3600 # 1 hour max - deploys should never take longer

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
            # Restricted to specific repos - not org-wide wildcard
            "token.actions.githubusercontent.com:sub" = var.allowed_repos
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

# -- S3 Frontend Deploy Policy --
# Scoped to specific frontend bucket ARNs only

resource "aws_iam_role_policy" "s3_frontend_deploy" {
  name = "s3-frontend-deploy"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3FrontendWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [for bucket in local.frontend_buckets : "arn:aws:s3:::${bucket}/*"]
      },
      {
        Sid    = "S3FrontendList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [for bucket in local.frontend_buckets : "arn:aws:s3:::${bucket}"]
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

# -- CloudFront Invalidation Policy --
# Scoped to specific distributions would be ideal, but IDs are dynamic.
# Account-scoped is the practical minimum.

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

# -- S3 Deploy Artifacts Policy --
# Write artifacts + read them back for SSM deploys

resource "aws_iam_role_policy" "s3_deploy_artifacts" {
  name = "s3-deploy-artifacts"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DeployArtifactsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.deploy_artifacts.arn}/*"
      },
      {
        Sid    = "S3DeployArtifactsList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.deploy_artifacts.arn
      }
    ]
  })
}

# -- S3 Deploy Metrics Policy --
# Write-only for metrics collection, read for weekly reports

resource "aws_iam_role_policy" "s3_deploy_metrics" {
  name = "s3-deploy-metrics"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3DeployMetricsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.deploy_metrics.arn}/*"
      },
      {
        Sid    = "S3DeployMetricsList"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.deploy_metrics.arn
      }
    ]
  })
}

# -- SSM Run Command Policy --
# Restricted to the specific deploy document - cannot run arbitrary SSM commands

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
        Condition = {
          StringEquals = {
            "ssm:document-name" = aws_ssm_document.deploy_api.name
          }
        }
      },
      {
        Sid    = "SSMGetCommandStatus"
        Effect = "Allow"
        Action = [
          "ssm:GetCommandInvocation"
        ]
        Resource = "*"
      }
    ]
  })
}

# -- EC2 Describe Policy --
# Read-only, needed to discover deploy targets by tag

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

# -- Deny Dangerous Actions --
# Explicit deny to prevent accidental privilege escalation

resource "aws_iam_role_policy" "deny_dangerous" {
  name = "deny-dangerous-actions"
  role = aws_iam_role.github_actions_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIAMChanges"
        Effect = "Deny"
        Action = [
          "iam:*",
          "sts:AssumeRole",
          "organizations:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDestructiveS3"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketPublicAccessBlock"
        ]
        Resource = "*"
      }
    ]
  })
}

# -- Output --

output "deploy_role_arn" {
  description = "ARN of the GitHub Actions deploy role"
  value       = aws_iam_role.github_actions_deploy.arn
}
