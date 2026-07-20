output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Use in each environment's backend.tf."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table. Use in each environment's backend.tf."
  value       = aws_dynamodb_table.lock.name
}

output "backend_config_hint" {
  description = "Copy these values into terraform/environments/*/backend.tf."
  value       = <<-EOT
    bucket         = "${aws_s3_bucket.state.id}"
    dynamodb_table = "${aws_dynamodb_table.lock.name}"
    region         = "${var.aws_region}"
    key            = "<environment-a|environment-b>/terraform.tfstate"
  EOT
}

output "pipeline_role_arn" {
  description = "ARN of the GitHub Actions pipeline role. Set this as the repo secret AWS_PIPELINE_ROLE_ARN. Null when create_pipeline_oidc = false."
  value       = var.create_pipeline_oidc ? aws_iam_role.pipeline[0].arn : null
}
