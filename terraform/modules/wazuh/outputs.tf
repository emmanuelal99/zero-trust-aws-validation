output "manager_private_ip" {
  description = "Private IP of the Wazuh manager for agent enrolment."
  value       = aws_instance.wazuh.private_ip
}

output "manager_public_ip" {
  description = "Public IP of the Wazuh manager (dashboard access, if in a public subnet)."
  value       = aws_instance.wazuh.public_ip
}

output "security_group_id" {
  description = "Security group ID of the Wazuh manager."
  value       = aws_security_group.wazuh.id
}
