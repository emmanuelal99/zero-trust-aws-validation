# Networking: VPC, public + private subnets, IGW, optional NAT, routes, optional VPC
# endpoints, and NACLs. Behaviour differs between the perimeter baseline (Env A) and the
# Zero Trust model (Env B) purely via the input variables.

data "aws_region" "current" {}

locals {
  tags = merge(var.tags, { Component = "networking" })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name_prefix}-igw" })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # Baseline exposes workloads directly => auto-assign public IPs. Zero Trust keeps
  # workloads in private subnets, so public subnets host only the ALB/NAT.
  map_public_ip_on_launch = !var.zero_trust

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-public-${count.index}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-private-${count.index}"
    Tier = "private"
  })
}

# ---------------------------------------------------------------------------
# NAT gateway (optional) — egress for private subnets
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count      = var.enable_nat ? 1 : 0
  domain     = "vpc"
  tags       = merge(local.tags, { Name = "${var.name_prefix}-nat-eip" })
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.tags, { Name = "${var.name_prefix}-nat" })
  depends_on    = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Network ACLs
# Baseline: default allow-all NACL (perimeter model relies on the edge firewall).
# Zero Trust: explicit deny-by-default private NACL that only permits intra-VPC + return
# traffic, demonstrating micro-segmentation at the subnet boundary.
# ---------------------------------------------------------------------------
resource "aws_network_acl" "private_zt" {
  count      = var.zero_trust ? 1 : 0
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.private[*].id
  tags       = merge(local.tags, { Name = "${var.name_prefix}-private-nacl" })
}

# Ingress: allow traffic originating inside the VPC only.
resource "aws_network_acl_rule" "private_zt_ingress_vpc" {
  count          = var.zero_trust ? 1 : 0
  network_acl_id = aws_network_acl.private_zt[0].id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
}

# Ingress: allow return traffic for outbound connections (ephemeral ports).
resource "aws_network_acl_rule" "private_zt_ingress_ephemeral" {
  count          = var.zero_trust ? 1 : 0
  network_acl_id = aws_network_acl.private_zt[0].id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

# Egress: allow all (egress governed by security groups + NAT/endpoints).
resource "aws_network_acl_rule" "private_zt_egress" {
  count          = var.zero_trust ? 1 : 0
  network_acl_id = aws_network_acl.private_zt[0].id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# VPC endpoints (optional) — keep AWS API traffic private (Zero Trust)
# ---------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.name_prefix}-vpce-sg"
  description = "Allow HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${var.name_prefix}-vpce-sg" })
}

locals {
  interface_endpoints = var.enable_vpc_endpoints ? toset([
    "ssm", "ssmmessages", "ec2messages", "secretsmanager", "kms", "logs",
  ]) : toset([])
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_endpoints
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = merge(local.tags, { Name = "${var.name_prefix}-vpce-${each.key}" })
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = merge(local.tags, { Name = "${var.name_prefix}-vpce-s3" })
}
