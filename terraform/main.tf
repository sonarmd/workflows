terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "sonarmd-terraform-state"
    key    = "cicd/workflows/terraform.tfstate"
    region = "us-east-2"
  }
}

provider "aws" {
  region = "us-east-2"

  default_tags {
    tags = {
      Project   = "SonarMD"
      ManagedBy = "terraform"
      Repo      = "sonarmd/workflows"
    }
  }
}

locals {
  github_org = "sonarmd"

  # Frontend S3 buckets (existing — not managed by this Terraform)
  frontend_buckets = {
    admin-dev    = "admin.dev.sonarmd.com"
    admin-stg    = "admin.stg.sonarmd.com"
    admin-prd    = "admin.sonarmd.com"
    patient-dev  = "my.dev.sonarmd.com"
    patient-stg  = "my.stg.sonarmd.com"
    patient-prd  = "my.sonarmd.com"
    provider-dev = "care.dev.sonarmd.com"
    provider-stg = "care.stg.sonarmd.com"
    provider-prd = "care.sonarmd.com"
    seat-dev     = "seat.dev.sonarmd.com"
    seat-stg     = "seat.stg.sonarmd.com"
    seat-prd     = "seat.sonarmd.com"
  }
}
