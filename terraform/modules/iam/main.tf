# IAM instance role. The privilege posture is the toggle:
#   Baseline  -> broad, wildcarded permissions (models over-permissioned SME instances).
#   Zero Trust -> least privilege: SSM core + scoped secret read + scoped KMS decrypt + logs.

locals {
  tags = merge(var.tags, { Component = "iam" })
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

# SSM Session Manager access (used as the sole access path under Zero Trust; harmless in
# the baseline). Requires no inbound SSH.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---------------------------------------------------------------------------
# Baseline: deliberately broad policy (wildcards) — this is what Prowler/Stratus should flag.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "broad" {
  count = var.zero_trust ? 0 : 1

  statement {
    sid    = "BroadReadWrite"
    effect = "Allow"
    actions = [
      "s3:*",
      "ec2:Describe*",
      "secretsmanager:GetSecretValue",
      "kms:Decrypt",
      "logs:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "broad" {
  count  = var.zero_trust ? 0 : 1
  name   = "${var.name_prefix}-broad-policy"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.broad[0].json
}

# ---------------------------------------------------------------------------
# Zero Trust: least-privilege scoped policy.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "scoped" {
  count = var.zero_trust ? 1 : 0

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      sid       = "ReadAppSecret"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptWithAppKey"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = var.kms_key_arns
    }
  }

  dynamic "statement" {
    for_each = var.artifact_bucket_arn != "" ? [1] : []
    content {
      sid       = "ReadAppArtifact"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${var.artifact_bucket_arn}/*"]
    }
  }

  statement {
    sid       = "AppLogging"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:CreateLogGroup"]
    resources = ["arn:aws:logs:*:*:log-group:/${var.name_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "scoped" {
  count  = var.zero_trust ? 1 : 0
  name   = "${var.name_prefix}-scoped-policy"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.scoped[0].json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.instance.name
  tags = local.tags
}
