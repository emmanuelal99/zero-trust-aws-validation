# App artifact delivery: zip the Logi-Track source and publish it to a private,
# encrypted S3 bucket. Instances pull + extract this at boot (Env B via the S3 VPC
# endpoint + scoped IAM read; Env A via its broad role). Identical in both
# environments so the app topology is a controlled variable.

locals {
  tags = merge(var.tags, { Component = "app-artifact" })
}

data "aws_caller_identity" "current" {}

data "archive_file" "app" {
  type        = "zip"
  source_dir  = var.app_source_dir
  output_path = "${path.module}/.build/${var.name_prefix}-app.zip"

  excludes = [
    ".DS_Store",
    ".git",
    ".gitignore",
    "venv",
    ".env",
    "db.sqlite3",
    "dump.rdb",
    "__pycache__",
    "shipping/__pycache__",
    "mylogistics/__pycache__",
  ]
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.name_prefix}-app-artifacts-${data.aws_caller_identity.current.account_id}"
  tags   = merge(local.tags, { Name = "${var.name_prefix}-app-artifacts" })
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      # Use the customer-managed CMK when provided (Zero Trust); otherwise SSE-S3.
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_object" "app" {
  bucket = aws_s3_bucket.artifacts.id
  key    = "app/${data.archive_file.app.output_md5}.zip"
  source = data.archive_file.app.output_path
  etag   = data.archive_file.app.output_md5

  # Ensure encryption config is in place before the object lands.
  depends_on = [aws_s3_bucket_server_side_encryption_configuration.artifacts]
}
