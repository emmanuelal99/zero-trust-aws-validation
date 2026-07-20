# Customer-managed KMS key (Zero Trust). When create = false the module produces null
# outputs and callers fall back to AWS-managed default encryption.

locals {
  tags = merge(var.tags, { Component = "kms" })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Key policy: keep the default root/IAM delegation, PLUS grant the Auto Scaling
# service-linked role the permissions it needs to launch instances with a
# CMK-encrypted EBS root volume. Without the CreateGrant statement, ASG-launched
# instances fail with Client.InvalidKMSKey.InvalidState and die seconds after
# launch (before user-data runs). A direct RunInstances call does not need this.
data "aws_iam_policy_document" "key" {
  count = var.create ? 1 : 0

  # Root account retains full control so IAM policies continue to govern the key
  # (the pipeline/admin role and the app instance role reach it via IAM).
  statement {
    sid       = "EnableRootAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Auto Scaling service-linked role: use of the key for EBS encryption.
  statement {
    sid    = "AllowAutoScalingUseOfKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
  }

  # Auto Scaling service-linked role: create grants for AWS resources (EBS).
  statement {
    sid       = "AllowAutoScalingCreateGrant"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_kms_key" "this" {
  count                   = var.create ? 1 : 0
  description             = var.description
  deletion_window_in_days = 7 # KMS hard minimum; cannot force-delete like a secret
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key[0].json
  tags                    = merge(local.tags, { Name = "${var.name_prefix}-cmk" })
}

resource "aws_kms_alias" "this" {
  count         = var.create ? 1 : 0
  name          = "alias/${var.name_prefix}-cmk"
  target_key_id = aws_kms_key.this[0].key_id
}
