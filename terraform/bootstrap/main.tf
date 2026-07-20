##############################################################################
# BOOTSTRAP - Terraform Remote State Backend
#
# This creates the S3 bucket + DynamoDB table used by every other Terraform
# root module (environments/dev, environments/prod) for remote state and
# state locking.
#
# WHY THIS IS SEPARATE:
# Terraform can't use a backend that doesn't exist yet ("chicken and egg"
# problem). So this module is applied ONCE, manually, with plain local
# state, before you ever run `terraform init` inside environments/*.
#
# Run this only once per AWS account/region. Do NOT re-run it per environment.
##############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Intentionally local state - this is the one exception in the whole repo.
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# S3 bucket to store all environment .tfstate files
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  # Safety net: prevents `terraform destroy` from ever deleting this bucket
  # by accident. Remove manually if you truly intend to tear it down.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name      = var.state_bucket_name
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled" # lets you recover a previous state file if one gets corrupted
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# DynamoDB table for state locking (prevents two people/pipelines from
# running `terraform apply` on the same state at the same time)
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST" # no capacity planning needed for a lock table
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name      = var.lock_table_name
    Purpose   = "terraform-state-locking"
    ManagedBy = "terraform-bootstrap"
  }
}
