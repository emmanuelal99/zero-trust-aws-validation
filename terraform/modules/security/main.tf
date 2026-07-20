# Security groups: the concrete difference between the perimeter baseline and Zero Trust.
#
# Baseline (zero_trust = false):
#   - App directly reachable from the internet on its port.
#   - SSH open to admin_cidr (broad).
#   - DB reachable from the whole VPC CIDR (flat internal trust).
#
# Zero Trust (zero_trust = true):
#   - App reachable ONLY from the ALB security group.
#   - No SSH (access via SSM Session Manager).
#   - DB reachable ONLY from the app security group.
#   - Egress restricted rather than allow-all.

locals {
  tags = merge(var.tags, { Component = "security" })
}

# ---------------------------------------------------------------------------
# ALB security group (both models expose the ALB to the internet)
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB ingress from the internet"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name_prefix}-alb-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "ALB egress to targets"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# App (EC2) security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Django app instance"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name_prefix}-app-sg" })
}

# Zero Trust: app port only from the ALB SG.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  count                        = var.zero_trust ? 1 : 0
  security_group_id            = aws_security_group.app.id
  description                  = "App port from ALB only"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Baseline: app port exposed to the internet directly (perimeter model).
resource "aws_vpc_security_group_ingress_rule" "app_public" {
  count             = var.zero_trust ? 0 : 1
  security_group_id = aws_security_group.app.id
  description       = "App port open to internet (baseline)"
  ip_protocol       = "tcp"
  from_port         = var.app_port
  to_port           = var.app_port
  cidr_ipv4         = "0.0.0.0/0"
}

# Baseline also allows the ALB to reach the app.
resource "aws_vpc_security_group_ingress_rule" "app_from_alb_baseline" {
  count                        = var.zero_trust ? 0 : 1
  security_group_id            = aws_security_group.app.id
  description                  = "App port from ALB (baseline)"
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
  referenced_security_group_id = aws_security_group.alb.id
}

# Baseline: SSH open to admin_cidr (broad by design). Zero Trust omits this entirely.
resource "aws_vpc_security_group_ingress_rule" "app_ssh" {
  count             = var.zero_trust ? 0 : 1
  security_group_id = aws_security_group.app.id
  description       = "SSH (baseline only)"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.admin_cidr
}

# Egress: baseline allow-all; Zero Trust restricted to HTTPS (AWS APIs / endpoints) + DB.
resource "aws_vpc_security_group_egress_rule" "app_all" {
  count             = var.zero_trust ? 0 : 1
  security_group_id = aws_security_group.app.id
  description       = "Egress all (baseline)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  count             = var.zero_trust ? 1 : 0
  security_group_id = aws_security_group.app.id
  description       = "HTTPS egress to AWS APIs / VPC endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  count                        = var.zero_trust ? 1 : 0
  security_group_id            = aws_security_group.app.id
  description                  = "DB egress to database SG"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.db.id
}

# Zero Trust needs some general HTTPS egress for package installs during boot / NAT path.
resource "aws_vpc_security_group_egress_rule" "app_https_internet" {
  count             = var.zero_trust ? 1 : 0
  security_group_id = aws_security_group.app.id
  description       = "HTTPS egress to internet (via NAT) for package installs"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Database (RDS) security group
# ---------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name_prefix}-db-sg"
  description = "RDS PostgreSQL"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name_prefix}-db-sg" })
}

# Zero Trust: DB only from the app SG.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  count                        = var.zero_trust ? 1 : 0
  security_group_id            = aws_security_group.db.id
  description                  = "DB from app SG only"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.app.id
}

# Baseline: DB reachable from the whole VPC (flat internal trust).
resource "aws_vpc_security_group_ingress_rule" "db_from_vpc" {
  count             = var.zero_trust ? 0 : 1
  security_group_id = aws_security_group.db.id
  description       = "DB from entire VPC (baseline flat trust)"
  ip_protocol       = "tcp"
  from_port         = var.db_port
  to_port           = var.db_port
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "db_all" {
  security_group_id = aws_security_group.db.id
  description       = "DB egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
