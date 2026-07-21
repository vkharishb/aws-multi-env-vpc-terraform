output "state_bucket_name" {
  description = "S3 bucket name - copy this into environments/*/backend.tf"
  value       = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  description = "DynamoDB table name - copy this into environments/*/backend.tf"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_region" {
  value = var.aws_region
}

output "github_actions_role_arn" {
  description = "Paste this into the GitHub repo secret AWS_OIDC_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}
