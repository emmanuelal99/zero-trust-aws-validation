output "trail_bucket_name" {
  description = "Name of the S3 bucket receiving CloudTrail logs (Wazuh wodle source)."
  value       = aws_s3_bucket.trail.id
}

output "trail_bucket_arn" {
  description = "ARN of the CloudTrail log bucket (for scoped Wazuh read policy)."
  value       = aws_s3_bucket.trail.arn
}

output "trail_name" {
  description = "Name of the CloudTrail trail."
  value       = aws_cloudtrail.this.name
}
