# Remote state backend. Fill in bucket/table from the bootstrap outputs, then run
# `terraform init`. Comment out the environment to be initialised locally first if
# the backend has not been bootstrapped yet.

terraform {
    backend "s3" {
    bucket         = "zt-dissertation-tfstate-emmanuelal99"
    key            = "environment-b/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "zt-dissertation-tf-locks"
    encrypt        = true
  }
}
