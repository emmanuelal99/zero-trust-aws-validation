variable "aws_region" {
  description = "AWS region for the state backend."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking."
  type        = string
  default     = "zt-dissertation-tf-locks"
}

variable "create_pipeline_oidc" {
  description = "Create the GitHub Actions OIDC provider + pipeline role. Enable once the GitHub repo exists."
  type        = bool
  default     = false
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the pipeline role, as 'owner/repo'. Required when create_pipeline_oidc = true."
  type        = string
  default     = ""
}
