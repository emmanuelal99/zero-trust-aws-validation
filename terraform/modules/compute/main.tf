# Compute: internet-facing ALB + Auto Scaling Group of EC2 instances running Logi-Track.
# User-data differs by model (secret retrieval vs plaintext injection, Wazuh agent enrol).

locals {
  tags = merge(var.tags, { Component = "compute" })
}

data "aws_ami" "al2023" {
  count       = var.ami_id == null ? 1 : 0
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

locals {
  ami_id = var.ami_id != null ? var.ami_id : data.aws_ami.al2023[0].id

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    zero_trust          = var.zero_trust
    app_port            = var.app_port
    aws_region          = var.aws_region
    db_host             = var.db_host
    db_name             = var.db_name
    db_username         = var.db_username
    db_password         = var.db_password
    db_secret_arn       = var.db_secret_arn
    secret_key          = var.secret_key
    email_host_user     = var.email_host_user
    email_host_password = var.email_host_password
    default_from_email  = var.default_from_email
    app_artifact_bucket = var.app_artifact_bucket
    app_artifact_key    = var.app_artifact_key
    alb_dns_name        = aws_lb.this.dns_name
    wazuh_manager_ip    = var.wazuh_manager_ip
    name_prefix         = var.name_prefix
  }))
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.alb_subnet_ids
  tags               = merge(local.tags, { Name = "${var.name_prefix}-alb" })
}

resource "aws_lb_target_group" "this" {
  name     = "${var.name_prefix}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    # The Django app has no dedicated /health route; the homepage ("/") returns 200
    # on GET without touching the database, so it is a safe liveness target.
    path                = "/"
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}

# ---------------------------------------------------------------------------
# Launch template + Auto Scaling Group
# ---------------------------------------------------------------------------
resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = local.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = local.user_data

  iam_instance_profile {
    name = var.instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = !var.zero_trust
    security_groups             = [var.app_sg_id]
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = var.ebs_encrypted
      kms_key_id  = var.ebs_encrypted ? var.kms_key_arn : null
    }
  }

  # Zero Trust: enforce IMDSv2 to blunt SSRF-based credential theft.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.zero_trust ? "required" : "optional"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${var.name_prefix}-app" })
  }

  tags = local.tags
}

resource "aws_autoscaling_group" "this" {
  name                      = "${var.name_prefix}-asg"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.desired_capacity
  vpc_zone_identifier       = var.app_subnet_ids
  target_group_arns         = [aws_lb_target_group.this.arn]
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  # How long Terraform waits for the ASG to report a healthy instance before
  # failing the apply. Raised for Zero Trust (Env B), whose boot is legitimately
  # slower (private subnet via NAT, S3 artifact via VPC endpoint, Secrets Manager
  # fetch). A high grace period also keeps a not-yet-healthy instance alive long
  # enough to SSM in and read /var/log/logitrack-bootstrap.log.
  wait_for_capacity_timeout = var.wait_for_capacity_timeout

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-app"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
