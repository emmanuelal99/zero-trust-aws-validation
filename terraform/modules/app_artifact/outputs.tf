output "bucket" {
  description = "Name of the artifact S3 bucket."
  value       = aws_s3_bucket.artifacts.bucket
}

output "bucket_arn" {
  description = "ARN of the artifact S3 bucket."
  value       = aws_s3_bucket.artifacts.arn
}

output "object_key" {
  description = "S3 key of the packaged app zip (content-addressed by md5)."
  value       = aws_s3_object.app.key
}
