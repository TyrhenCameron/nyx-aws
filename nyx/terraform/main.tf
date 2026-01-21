terraform {
  required_version = ">=1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # needed to package Lambda code
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # backend config commented out for now
  # backend "s3" {
  #   bucket = "terraform-state-bucket"
  #   key = "nemesis/terraform.tfstate"
  #   region = "ap-northeast-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# get current AWS account ID
data "aws_caller_identify" "current" {}

# Get current region
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identify.current.account_id
  region     = data.aws_region.current.name

  # naming convention
  name_prefix = "${var.project_name} - ${var.environment}"
}
