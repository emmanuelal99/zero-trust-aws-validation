output "flow_log_group_name" {
  description = "CloudWatch Log Group receiving VPC Flow Logs."
  value       = aws_cloudwatch_log_group.flow.name
}

output "flow_log_id" {
  description = "ID of the VPC Flow Log."
  value       = aws_flow_log.this.id
}
