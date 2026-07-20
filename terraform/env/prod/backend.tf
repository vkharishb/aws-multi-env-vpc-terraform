##############################################################################
# REMOTE STATE BACKEND - prod
# Same bucket/table as dev, different state file KEY - this is what keeps
# dev and prod state completely isolated from each other.
##############################################################################
terraform {
  backend "s3" {
    bucket         = "harish-tfstate-multienv-vpc"
    key            = "environments/prod/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
