output "key_arn" {
  description = "ARN of the KMS key, or null when not created."
  value       = var.create ? aws_kms_key.this[0].arn : null
}

output "key_id" {
  description = "ID of the KMS key, or null when not created."
  value       = var.create ? aws_kms_key.this[0].key_id : null
}
