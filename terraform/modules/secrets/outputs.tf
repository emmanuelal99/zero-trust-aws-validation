output "secret_arn" {
  description = "ARN of the DB credentials secret, or null when not created."
  value       = var.create ? aws_secretsmanager_secret.db[0].arn : null
}

output "secret_name" {
  description = "Name of the DB credentials secret, or null when not created."
  value       = var.create ? aws_secretsmanager_secret.db[0].name : null
}
