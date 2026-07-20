# Bootstrap: remote Terraform state backend (run once, uses local state itself).
# Creates the S3 bucket + DynamoDB lock table that Environment A and B reference in
# their backend.tf. Kept separate so the backend exists before any environment init.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "zt-dissertation"
      Component = "tf-state-backend"
      ManagedBy = "terraform"
    }
  }
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  # State is precious: block accidental deletion of the backend bucket.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC federation for the attack pipeline.
#   Off by default (create_pipeline_oidc = false) so state can be bootstrapped
#   before a GitHub repo exists. Enable once the repo is pushed, then set the
#   repo secret AWS_PIPELINE_ROLE_ARN to the `pipeline_role_arn` output.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_pipeline_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fca",
  ]
}

data "aws_iam_policy_document" "pipeline_assume" {
  count = var.create_pipeline_oidc ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope on `sub` (the claim AWS mandates). This account's `sub` embeds numeric IDs
    # (repo:owner@<id>/repo@<id>:ref:refs/heads/<branch>), so the wildcards after the
    # owner and repo names absorb the `@<id>` suffixes while still pinning this exact
    # owner/repo and restricting to branch refs only. `github_repo` = "owner/repo" is
    # split so the `*` lands between name and suffix, not across the `/`.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${split("/", var.github_repo)[0]}*/${split("/", var.github_repo)[1]}*:ref:refs/heads/*"]
    }
  }
}

resource "aws_iam_role" "pipeline" {
  count = var.create_pipeline_oidc ? 1 : 0

  name               = "zt-dissertation-pipeline-role"
  assume_role_policy = data.aws_iam_policy_document.pipeline_assume[0].json

  tags = {
    Component = "ci-pipeline"
  }
}

# The pipeline runs `terraform apply` (creates VPC/EC2/RDS/IAM/KMS/Secrets/WAF/
# CloudTrail/S3), Prowler (read-all posture assessment) and drift injection
# (mutates SGs/IAM/S3/CloudTrail/EBS/password-policy). AdministratorAccess is the
# pragmatic single-account grant for a self-contained dissertation pipeline.
resource "aws_iam_role_policy_attachment" "pipeline_admin" {
  count = var.create_pipeline_oidc ? 1 : 0

  role       = aws_iam_role.pipeline[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
