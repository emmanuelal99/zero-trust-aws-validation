# Account/VPC-level detective controls — Environment B ONLY (Table 3.1). Keeping
# these out of Environment A is deliberate: A's absence of centralised logging is
# the perimeter-baseline finding, not an omission.
#
# GuardDuty is NOT provisioned: the AWS account is on the Free Plan, which restricts
# the service, and GuardDuty is not in this study's MTTD detection path (detection
# runs CloudTrail -> Wazuh wodle -> custom rules). VPC Flow Logs remain enabled.

locals {
  tags = merge(var.tags, { Component = "monitoring" })
}

# ---------------------------------------------------------------------------
# VPC Flow Logs -> CloudWatch Logs. Captures ALL traffic for the VPC.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow" {
  name              = "/${var.name_prefix}/vpc/flow-logs"
  retention_in_days = var.flow_log_retention_days
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow" {
  name               = "${var.name_prefix}-vpc-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "flow" {
  statement {
    sid    = "PublishFlowLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow" {
  name   = "${var.name_prefix}-vpc-flow-logs-policy"
  role   = aws_iam_role.flow.id
  policy = data.aws_iam_policy_document.flow.json
}

resource "aws_flow_log" "this" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow.arn
  iam_role_arn         = aws_iam_role.flow.arn
  tags                 = merge(local.tags, { Name = "${var.name_prefix}-vpc-flow-log" })
}
