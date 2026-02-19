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
    key    = "cicd/workflows.tfstate"
    region = "us-east-2"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "sonarmd-cicd"
      ManagedBy = "terraform"
      Repo      = "sonarmd/workflows"
    }
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "github_org" {
  description = "GitHub organization name"
  type        = string
  default     = "sonarmd"
}
