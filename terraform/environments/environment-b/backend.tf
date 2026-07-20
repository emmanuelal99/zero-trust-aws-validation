# Remote state backend. Fill in bucket/table from the bootstrap outputs, then run
# `terraform init`. Commented out so the environment can be initialised locally first if
# the backend has not been bootstrapped yet.

# terraform {
#   backend "s3" {
#     bucket         = "zt-dissertation-tfstate-CHANGEME"
#     key            = "environment-b/terraform.tfstate"
#     region         = "eu-west-2"
#     dynamodb_table = "zt-dissertation-tf-locks"
#     encrypt        = true
#   }
# }
