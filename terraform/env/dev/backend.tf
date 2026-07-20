##############################################################################
# REMOTE STATE BACKEND - dev
#
# Values here come from the outputs of `bootstrap/` (run that first).
# Terraform backend blocks cannot use variables, so these are hardcoded -
# that's expected and normal for backend configuration.
##############################################################################
terraform {
  backend "s3" {
    bucket         = "harish-tfstate-multienv-vpc" # must match bootstrap's state_bucket_name
    key            = "environments/dev/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks" # must match bootstrap's lock_table_name
    encrypt        = true
  }
}
