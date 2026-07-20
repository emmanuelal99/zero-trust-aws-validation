# ===========================================================================
# Environment B — Zero Trust security model.
#
# Same shared modules as Environment A, with every zero_trust / hardening toggle flipped
# to its SECURE value. A and B differ only by configuration — a controlled-variable
# comparison for the dissertation.
#
# Zero Trust characteristics:
#   - App + DB + Wazuh run in PRIVATE subnets across two AZs; only the ALB and NAT sit
#     in public subnets. NAT gateway + interface/gateway VPC endpoints for AWS APIs.
#   - Deny-by-default private NACLs; SG-to-SG micro-segmentation
#     (ALB -> app -> DB), no public app port, no inbound SSH.
#   - Least-privilege instance IAM role (scoped secret read + scoped KMS decrypt + logs).
#   - Customer-managed KMS CMK; encrypted EBS + RDS at rest.
#   - DB credentials in Secrets Manager, pulled at boot via the instance role.
#   - WAFv2 fronting the ALB. Identity-aware auth (Cognito OIDC) is scaffolded but OFF.
#   - Access to instances via SSM Session Manager only (no key pair, no port 22).
# ===========================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge({
      Project     = "zt-dissertation"
      Environment = "B-zerotrust"
      Model       = "zero-trust"
      ManagedBy   = "terraform"
    }, var.tags)
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# DB master password — stored in Secrets Manager (not injected as plaintext).
resource "random_password" "db" {
  length  = 20
  special = false
}

# Django SECRET_KEY — generated fresh, stored in Secrets Manager (not plaintext).
# Alphanumeric only to avoid shell/JSON escaping in user-data.
resource "random_password" "secret_key" {
  length  = 50
  special = false
}

locals {
  # Spread compute across at least two AZs (one per subnet CIDR).
  azs        = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  zero_trust = true
}

# ---------------------------------------------------------------------------
# Customer-managed KMS key — encrypts EBS, RDS and the DB secret.
# ---------------------------------------------------------------------------
module "kms" {
  source = "../../modules/kms"

  name_prefix = var.name_prefix
  create      = true
  description = "Zero Trust CMK for ${var.name_prefix} (EBS, RDS, Secrets Manager)"
}

# ---------------------------------------------------------------------------
# App artifact — package Logi-Track and publish to a private, CMK-encrypted
# S3 bucket. Instances pull it at boot via the scoped instance role.
# ---------------------------------------------------------------------------
module "app_artifact" {
  source = "../../modules/app_artifact"

  name_prefix    = var.name_prefix
  app_source_dir = "${path.root}/../../../app/logi-track"
  kms_key_arn    = module.kms.key_arn
}

# ---------------------------------------------------------------------------
# Networking — private workloads, NAT egress, VPC endpoints, deny NACLs.
# ---------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  name_prefix          = var.name_prefix
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  zero_trust           = local.zero_trust
  enable_nat           = true # private app subnets need egress for boot / AWS APIs
  enable_vpc_endpoints = true # keep SSM/Secrets/KMS/S3 traffic off the public internet
}

# ---------------------------------------------------------------------------
# Security groups — SG-to-SG micro-segmentation, no public app port, no SSH.
# ---------------------------------------------------------------------------
module "security" {
  source = "../../modules/security"

  name_prefix = var.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr
  zero_trust  = local.zero_trust
  admin_cidr  = var.admin_cidr
}

# ---------------------------------------------------------------------------
# Database — private subnets, encrypted at rest with the CMK, not public.
# ---------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  name_prefix         = var.name_prefix
  subnet_ids          = module.networking.private_subnet_ids
  db_sg_id            = module.security.db_sg_id
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = random_password.db.result
  instance_class      = var.db_instance_class
  publicly_accessible = false
  storage_encrypted   = true
  kms_key_arn         = module.kms.key_arn
}

# ---------------------------------------------------------------------------
# Secrets — DB credentials in Secrets Manager, encrypted with the CMK.
# ---------------------------------------------------------------------------
module "secrets" {
  source = "../../modules/secrets"

  name_prefix         = var.name_prefix
  create              = true
  kms_key_id          = module.kms.key_arn
  db_username         = var.db_username
  db_password         = random_password.db.result
  db_host             = module.database.db_address
  db_name             = module.database.db_name
  db_port             = 5432
  secret_key          = random_password.secret_key.result
  email_host_user     = var.email_host_user
  email_host_password = var.email_host_password
  default_from_email  = var.default_from_email
}

# ---------------------------------------------------------------------------
# IAM — least-privilege instance role scoped to the app secret and CMK.
# ---------------------------------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  name_prefix         = var.name_prefix
  zero_trust          = local.zero_trust
  secret_arns         = [module.secrets.secret_arn]
  kms_key_arns        = [module.kms.key_arn]
  artifact_bucket_arn = module.app_artifact.bucket_arn
}

# ---------------------------------------------------------------------------
# CloudTrail — Zero Trust CONTROL (Table 3.1), Environment B ONLY. Management
# events land in a private S3 bucket that the Wazuh wodle polls for detection.
# ---------------------------------------------------------------------------
module "cloudtrail" {
  source = "../../modules/cloudtrail"

  name_prefix = var.name_prefix
}

# ---------------------------------------------------------------------------
# Monitoring — VPC Flow Logs to CloudWatch (Table 3.1), Environment B ONLY.
# Environment A stays without them by design. GuardDuty is not provisioned
# (Free-Plan restriction; not in the CloudTrail -> Wazuh MTTD detection path).
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix = var.name_prefix
  vpc_id      = module.networking.vpc_id
}

# ---------------------------------------------------------------------------
# Wazuh manager — in a private subnet, reached via SSM (no public IP). Given its
# own scoped role and pointed at the CloudTrail bucket for cloud-layer detection.
# ---------------------------------------------------------------------------
module "wazuh" {
  source = "../../modules/wazuh"
  count  = var.deploy_wazuh ? 1 : 0

  name_prefix       = var.name_prefix
  vpc_id            = module.networking.vpc_id
  subnet_id         = module.networking.private_subnet_ids[0]
  vpc_cidr          = module.networking.vpc_cidr
  admin_cidr        = var.admin_cidr
  aws_region        = var.aws_region
  trail_bucket_name = module.cloudtrail.trail_bucket_name
  trail_bucket_arn  = module.cloudtrail.trail_bucket_arn
}

# ---------------------------------------------------------------------------
# Compute — ALB in public subnets, app ASG in private subnets across two AZs.
# Encrypted EBS, IMDSv2 required, DB creds fetched from Secrets Manager at boot.
# ---------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  name_prefix           = var.name_prefix
  zero_trust            = local.zero_trust
  vpc_id                = module.networking.vpc_id
  alb_subnet_ids        = module.networking.public_subnet_ids
  app_subnet_ids        = module.networking.private_subnet_ids
  alb_sg_id             = module.security.alb_sg_id
  app_sg_id             = module.security.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  key_name              = null # SSM only, no SSH
  ebs_encrypted         = true
  kms_key_arn           = module.kms.key_arn

  # ZT boot is slower (NAT egress, S3 artifact via VPC endpoint, Secrets Manager
  # fetch, Wazuh). Give the apply room to reach healthy, and keep an unhealthy
  # instance alive ~20 min so it can be SSM'd into to read the bootstrap log.
  health_check_grace_period = 1200
  wait_for_capacity_timeout = "25m"

  # Zero Trust: credentials come from Secrets Manager, not plaintext user-data.
  db_host       = module.database.db_address
  db_name       = module.database.db_name
  db_secret_arn = module.secrets.secret_arn
  aws_region    = var.aws_region

  # App artifact pulled from S3 at boot.
  app_artifact_bucket = module.app_artifact.bucket
  app_artifact_key    = module.app_artifact.object_key

  wazuh_manager_ip = var.deploy_wazuh ? module.wazuh[0].manager_private_ip : ""
}

# ---------------------------------------------------------------------------
# Edge — WAFv2 fronting the ALB. Cognito OIDC scaffolded but OFF by default.
# ---------------------------------------------------------------------------
module "edge" {
  source = "../../modules/edge"

  name_prefix = var.name_prefix
  enable_waf  = true
  alb_arn     = module.compute.alb_arn

  identity_aware_auth   = var.identity_aware_auth
  listener_arn          = module.compute.listener_arn
  target_group_arn      = module.compute.target_group_arn
  cognito_callback_urls = var.cognito_callback_urls
}
