# Remote state backend. Comment out to run on LOCAL state.
# To use remote state: apply terraform/bootstrap first, confirm the bucket name below
# matches its state_bucket_name output, uncomment, then run:
#   terraform init -migrate-state
# The bucket name must match bootstrap/terraform.tfvars.

terraform {
    backend "s3" {
    bucket         = "zt-dissertation-tfstate-emmanuelal99"
    key            = "environment-a/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "zt-dissertation-tf-locks"
    encrypt        = true
  }
}
