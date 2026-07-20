# Wazuh manager (single-node all-in-one) on EC2. Agents on the app instances enrol here;
# its alerts feed the MTTD and CDI metrics.

locals {
  tags = merge(var.tags, { Component = "wazuh" })
  # Cloud detection (CloudTrail wodle + AWS rules) only where a trail bucket is supplied.
  # Env B passes the trail bucket; Env A leaves it empty -> no cloud detection, MTTD
  # coverage = 0 by design (the perimeter-baseline finding).
  cloud_detection = var.trail_bucket_name != "" && var.trail_bucket_arn != ""
}

# ---------------------------------------------------------------------------
# Dedicated Wazuh instance role — NOT the shared app role. SSM for management,
# plus a scoped read on the CloudTrail bucket (Env B only). Keeps the app-tier
# Zero Trust role minimal (no S3 CloudTrail read leaks into the app instances).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "wazuh" {
  name               = "${var.name_prefix}-wazuh-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.wazuh.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped CloudTrail-bucket read for the AWS-S3 wodle (Env B only). No PutObject,
# no wildcard — just list + get on the one trail bucket. SSE-S3 trail => no kms:Decrypt.
data "aws_iam_policy_document" "trail_read" {
  count = local.cloud_detection ? 1 : 0

  statement {
    sid       = "ListTrailBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [var.trail_bucket_arn]
  }

  statement {
    sid       = "ReadTrailObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.trail_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "trail_read" {
  count  = local.cloud_detection ? 1 : 0
  name   = "${var.name_prefix}-wazuh-trail-read"
  role   = aws_iam_role.wazuh.id
  policy = data.aws_iam_policy_document.trail_read[0].json
}

resource "aws_iam_instance_profile" "wazuh" {
  name = "${var.name_prefix}-wazuh-profile"
  role = aws_iam_role.wazuh.name
  tags = local.tags
}

data "aws_ami" "al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "wazuh" {
  name        = "${var.name_prefix}-wazuh-sg"
  description = "Wazuh manager: agent enrolment + dashboard"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name_prefix}-wazuh-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "agent_events" {
  security_group_id = aws_security_group.wazuh.id
  description       = "Agent events from VPC"
  ip_protocol       = "tcp"
  from_port         = 1514
  to_port           = 1514
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "agent_enroll" {
  security_group_id = aws_security_group.wazuh.id
  description       = "Agent enrolment from VPC"
  ip_protocol       = "tcp"
  from_port         = 1515
  to_port           = 1515
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "dashboard" {
  security_group_id = aws_security_group.wazuh.id
  description       = "Wazuh dashboard (admin)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.admin_cidr
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.wazuh.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "wazuh" {
  ami                    = var.ami_id != null ? var.ami_id : data.aws_ami.al2023[0].id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.wazuh.name
  vpc_security_group_ids = [aws_security_group.wazuh.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > >(tee /var/log/wazuh-install.log) 2>&1
    # Pin the clock to UTC so alerts.json timestamps are UTC — the MTTD export filters
    # alerts by a UTC cutoff, and Wazuh writes timestamps in the host's local zone.
    timedatectl set-timezone UTC || true
    dnf -y update
    curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
    bash ./wazuh-install.sh -a -i || echo "WARN: wazuh-install returned non-zero"
    %{ if local.cloud_detection ~}

    # -----------------------------------------------------------------------
    # Cloud detection (Environment B): poll the CloudTrail bucket via the Wazuh
    # AWS-S3 wodle and add custom local rules that fire on the five attacker API
    # calls the pipeline detonates. rule.id + rule.mitre.id land in alerts.json;
    # metrics/compute_metrics.py correlates them for MTTD.
    # -----------------------------------------------------------------------
    # Custom rules keyed on the CloudTrail event name (data.aws.eventName). if_sid
    # 80200 is Wazuh's base Amazon rule, so these only evaluate on decoded AWS events.
    cat > /var/ossec/etc/rules/local_rules.xml <<'XMLEOF'
    <group name="amazon,aws,cloudtrail,attack,">
      <rule id="100810" level="12">
        <if_sid>80200</if_sid>
        <field name="aws.eventName">^StopLogging$</field>
        <description>CloudTrail logging stopped (defense evasion).</description>
        <mitre><id>T1562.008</id></mitre>
      </rule>
      <rule id="100811" level="12">
        <if_sid>80200</if_sid>
        <field name="aws.eventName">^DeleteTrail$</field>
        <description>CloudTrail trail deleted (defense evasion).</description>
        <mitre><id>T1562.008</id></mitre>
      </rule>
      <rule id="100812" level="12">
        <if_sid>80200</if_sid>
        <field name="aws.eventName">^CreateUser$</field>
        <description>IAM user created (persistence).</description>
        <mitre><id>T1136.003</id></mitre>
      </rule>
      <rule id="100813" level="12">
        <if_sid>80200</if_sid>
        <field name="aws.eventName">^BatchGetSecretValue$</field>
        <description>Bulk Secrets Manager retrieval (credential access).</description>
        <mitre><id>T1552.007</id></mitre>
      </rule>
      <rule id="100814" level="12">
        <if_sid>80200</if_sid>
        <field name="aws.eventName">^AuthorizeSecurityGroupIngress$</field>
        <description>Security group ingress opened (defense evasion / exposure).</description>
        <mitre><id>T1562.007</id></mitre>
      </rule>
    </group>
    XMLEOF
    chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml || true

    # Insert the AWS-S3 (cloudtrail) wodle just before </ossec_config>. Poll every
    # 1 min to keep the poll component of the detection latency small; the residual
    # floor is CloudTrail's own delivery latency (~5 min, occasionally 15).
    cat > /tmp/wazuh-aws-wodle.xml <<'WODLEEOF'
      <wodle name="aws-s3">
        <disabled>no</disabled>
        <interval>1m</interval>
        <run_on_start>yes</run_on_start>
        <bucket type="cloudtrail">
          <name>${var.trail_bucket_name}</name>
          <regions>${var.aws_region}</regions>
        </bucket>
      </wodle>
    WODLEEOF
    python3 - <<'PYEOF'
    p = "/var/ossec/etc/ossec.conf"
    w = open("/tmp/wazuh-aws-wodle.xml").read()
    s = open(p).read()
    if "aws-s3" not in s:
        s = s.replace("</ossec_config>", w + "\n</ossec_config>", 1)
        open(p, "w").write(s)
    PYEOF
    systemctl restart wazuh-manager || echo "WARN: wazuh-manager restart failed"
    %{ endif ~}
  EOF

  tags = merge(local.tags, { Name = "${var.name_prefix}-wazuh" })
}
