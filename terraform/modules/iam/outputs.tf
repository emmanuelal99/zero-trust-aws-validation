output "instance_profile_name" {
  description = "Name of the EC2 instance profile."
  value       = aws_iam_instance_profile.instance.name
}

output "role_arn" {
  description = "ARN of the instance role."
  value       = aws_iam_role.instance.arn
}

output "role_name" {
  description = "Name of the instance role."
  value       = aws_iam_role.instance.name
}
