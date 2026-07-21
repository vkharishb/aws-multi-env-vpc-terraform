##############################################################################
# BOOTSTRAP - Terraform Remote State Backend and GitHub Actions OIDC
#
# This root module creates:
#   1. S3 bucket for Terraform remote state
#   2. DynamoDB table for Terraform state locking
#   3. GitHub Actions OIDC provider (or reuses an existing provider)
#   4. IAM role assumed by GitHub Actions
#
# Bootstrap intentionally uses local Terraform state. Run it manually before
# running Terraform from terraform/env/dev or terraform/env/prod.
##############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

##############################################################################
# Terraform remote-state S3 bucket
##############################################################################

resource "aws_s3_bucket" "terraform_state" {
  bucket        = var.state_bucket_name
  force_destroy = true

  tags = {
    Name      = var.state_bucket_name
    Purpose   = "terraform-remote-state"
    ManagedBy = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
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
  bucket = aws_s3_bucket.terraform_state.id

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

##############################################################################
# Terraform state-locking DynamoDB table
##############################################################################

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
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

##############################################################################
# GitHub Actions OIDC provider
#
# Set create_oidc_provider = true when the provider does not exist.
# Set create_oidc_provider = false when it already exists in this AWS account.
##############################################################################

data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

##############################################################################
# IAM trust policy for GitHub Actions
#
# Supports both:
#   - Previous GitHub OIDC subject format
#   - Immutable owner-ID/repository-ID subject format
##############################################################################

data "aws_iam_policy_document" "github_oidc_trust" {
  statement {
    sid     = "AllowGitHubRepositoryOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type = "Federated"

      identifiers = [
        local.oidc_provider_arn
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"

      values = [
        # Previous GitHub OIDC subject format.
        "repo:${var.github_repo}:*",

        # Immutable GitHub OIDC subject format for this repository.
        "repo:vkharishb@218270518/aws-multi-env-vpc-terraform@1306225071:*"
      ]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  # Preserve the existing role name so the GitHub secret does not need to
  # change when this role already exists.
  name               = "github-actions-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_oidc_trust.json

  tags = {
    Purpose   = "github-actions-oidc"
    ManagedBy = "terraform-bootstrap"
  }
}

##############################################################################
# Managed policy attachments
##############################################################################

resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "elb" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
}

resource "aws_iam_role_policy_attachment" "autoscaling" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AutoScalingFullAccess"
}

##############################################################################
# Additional scoped permissions
##############################################################################

data "aws_iam_policy_document" "github_actions_scoped_extra" {
  statement {
    sid    = "IamScopedToProjectRoles"
    effect = "Allow"

    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:PassRole"
    ]

    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-app-role-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*-app-profile-*"
    ]
  }

  statement {
    sid    = "StateBucketAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
  }

  statement {
    sid    = "StateLockTableAccess"
    effect = "Allow"

    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"
    ]

    resources = [
      aws_dynamodb_table.terraform_locks.arn
    ]
  }

  statement {
    sid    = "SSMAndVpcEndpointVisibility"
    effect = "Allow"

    actions = [
      "ssm:DescribeInstanceInformation",
      "ec2:DescribeVpcEndpoints"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_scoped_extra" {
  name   = "github-actions-scoped-extra"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_scoped_extra.json
}
