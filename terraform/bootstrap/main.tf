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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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

  # Temporarily true to allow a full teardown (deletes all object versions
  # too, since versioning is enabled). Set back to false if you keep this
  # bucket around long-term - it's a safety net against `terraform destroy`
  # silently wiping out every environment's state history.
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

##############################################################################
# GITHUB OIDC -> AWS TRUST
#
# Lets GitHub Actions assume an AWS IAM role using short-lived tokens signed
# by GitHub, with NO long-lived AWS access keys stored in GitHub.
#
# An AWS account can only have ONE `token.actions.githubusercontent.com`
# OIDC provider. Rather than assuming it always needs to be imported (which
# breaks the moment the resource's existence changes - e.g. it gets
# destroyed elsewhere), this checks for it first via a data source and only
# creates it if var.create_oidc_provider says it isn't there yet.
##############################################################################

data "aws_caller_identity" "current" {}

# CHECK: look up an already-existing provider (only reads when
# create_oidc_provider = false - set that if one already exists in this
# account, e.g. created by another project or via the console).
data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# Fetches GitHub's actual current TLS certificate chain and computes the
# correct SHA1 thumbprint from it - avoids hand-typing a 40-character hex
# string (easy to get wrong) and stays correct if GitHub ever rotates certs.
data "tls_certificate" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

# CREATE: only runs when create_oidc_provider = true (the default - use
# this the first time, or any time you've confirmed nothing exists yet).
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # Root CA thumbprint (last certificate in the chain) - AWS no longer
  # actually validates this for well-known providers, but the resource
  # still requires a correctly-sized (40 hex char) value.
  thumbprint_list = [
    data.tls_certificate.github_actions[0].certificates[length(data.tls_certificate.github_actions[0].certificates) - 1].sha1_fingerprint,
  ]
}

# ATTACH: whichever one actually applies (checked-existing or just-created)
# feeds into the IAM role's trust policy below.
locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
}

# ---------------------------------------------------------------------------
# Trust policy - ONLY workflows running in var.github_repo may assume this
# role. Tighten the `sub` condition further (e.g. to specific branches) if
# you want to be stricter than "any workflow in this repo."
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}


resource "aws_iam_role" "github_actions" {
  name               = "github-actions-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_actions_trust.json

  tags = {
    Purpose   = "github-actions-oidc"
    ManagedBy = "terraform-bootstrap"
  }
}

# ---------------------------------------------------------------------------
# Permissions - broader managed policies for the "regular" AWS services this
# project touches, plus a tightly-scoped inline policy for IAM (the most
# dangerous thing to leave wide open) and for the specific S3/DynamoDB state
# backend resources created above.
# ---------------------------------------------------------------------------
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

data "aws_iam_policy_document" "github_actions_scoped_extra" {
  # IAM - restricted to role/instance-profile names this project creates
  # (see modules/asg - name_prefix = "${var.name}-app-role-" etc.)
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
      "iam:PassRole",
    ]
    resources = [
      "arn:aws:iam::*:role/*-app-role-*",
      "arn:aws:iam::*:instance-profile/*-app-profile-*",
    ]
  }

  # State backend access - scoped to exactly the bucket/table created above
  statement {
    sid    = "StateBucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  statement {
    sid    = "StateLockTableAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [
      aws_dynamodb_table.terraform_locks.arn,
    ]
  }

  # SSM/VPC endpoint visibility - covers what the vpc-endpoints module manages
  statement {
    sid    = "SSMDescribe"
    effect = "Allow"
    actions = [
      "ssm:DescribeInstanceInformation",
      "ec2:DescribeVpcEndpoints",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_scoped_extra" {
  name   = "github-actions-scoped-extra"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_scoped_extra.json
}
