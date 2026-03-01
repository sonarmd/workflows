# S3 Bucket: sonarmd-deploy-artifacts
# Stores API build artifacts and configuration files for SSM deployments

resource "aws_s3_bucket" "deploy_artifacts" {
  bucket = "sonarmd-deploy-artifacts"

  tags = {
    Name = "sonarmd-deploy-artifacts"
  }
}

resource "aws_s3_bucket_versioning" "deploy_artifacts" {
  bucket = aws_s3_bucket.deploy_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy_artifacts" {
  bucket = aws_s3_bucket.deploy_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "deploy_artifacts" {
  bucket = aws_s3_bucket.deploy_artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_public_access_block" "deploy_artifacts" {
  bucket = aws_s3_bucket.deploy_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "deploy_artifacts_tls" {
  bucket = aws_s3_bucket.deploy_artifacts.id

  # Ensure public access block is applied first
  depends_on = [aws_s3_bucket_public_access_block.deploy_artifacts]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.deploy_artifacts.arn,
          "${aws_s3_bucket.deploy_artifacts.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# S3 Bucket: sonarmd-deploy-metrics
# Stores deploy event JSON logs for KPI reporting

resource "aws_s3_bucket" "deploy_metrics" {
  bucket = "sonarmd-deploy-metrics"

  tags = {
    Name = "sonarmd-deploy-metrics"
  }
}

resource "aws_s3_bucket_versioning" "deploy_metrics" {
  bucket = aws_s3_bucket.deploy_metrics.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "deploy_metrics" {
  bucket = aws_s3_bucket.deploy_metrics.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "deploy_metrics" {
  bucket = aws_s3_bucket.deploy_metrics.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "deploy_metrics_tls" {
  bucket = aws_s3_bucket.deploy_metrics.id

  depends_on = [aws_s3_bucket_public_access_block.deploy_metrics]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.deploy_metrics.arn,
          "${aws_s3_bucket.deploy_metrics.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ── Outputs ──

output "deploy_artifacts_bucket" {
  description = "Name of the deploy artifacts S3 bucket"
  value       = aws_s3_bucket.deploy_artifacts.bucket
}

output "deploy_metrics_bucket" {
  description = "Name of the deploy metrics S3 bucket"
  value       = aws_s3_bucket.deploy_metrics.bucket
}
