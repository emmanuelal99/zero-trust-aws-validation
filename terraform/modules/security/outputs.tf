output "alb_sg_id" {
  description = "Security group ID for the ALB."
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security group ID for the app instances."
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "Security group ID for the database."
  value       = aws_security_group.db.id
}
