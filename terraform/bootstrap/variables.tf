variable "aws_region" {
  description = "AWS region to create the backend resources in"
  type        = string
  default     = "ap-south-1"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state. Must be changed - S3 bucket names are unique across ALL AWS accounts."
  type        = string
  default     = "harish-tfstate-multienv-vpc" # CHANGE THIS before applying
}

variable "lock_table_name" {
  description = "DynamoDB table name used for Terraform state locking"
  type        = string
  default     = "terraform-locks"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the OIDC role, format: owner/repo"
  type        = string
  default     = "vkharishb/aws-multi-env-vpc-terraform"
}

variable "create_oidc_provider" {
  description = "true = create the token.actions.githubusercontent.com OIDC provider (default - use this if none exists yet in your account). false = look up an already-existing one instead (an AWS account can only have one)."
  type        = bool
  default     = true
}
