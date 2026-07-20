# Remote state backend. Commented out so the first apply can run on LOCAL state.
# To use remote state: apply terraform/bootstrap first, confirm the bucket name below
# matches its state_bucket_name output, uncomment, then run:
#   terraform init -migrate-state
# The bucket name must match bootstrap/terraform.tfvars (change both if you edit it).

# terraform {
#   backend "s3" {
#     bucket         = "zt-dissertation-tfstate-euw2-7q3k9"
#     key            = "environment-a/terraform.tfstate"
#     region         = "eu-west-2"
#     dynamodb_table = "zt-dissertation-tf-locks"
#     encrypt        = true
#   }
# }
