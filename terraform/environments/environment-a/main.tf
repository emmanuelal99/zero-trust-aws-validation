# ===========================================================================
# Environment A — Perimeter / baseline security model.
#
# Every zero_trust / hardening toggle is set to its INSECURE value so the pipeline
# (Trivy/Prowler/Nuclei/Stratus) has a realistic weak baseline to attack. Environment B
# reuses the same modules with the toggles flipped.
#
# Baseline characteristics:
#   - App + DB run in PUBLIC subnets, app port and SSH open to the internet.
#   - Flat internal trust: DB reachable from the whole VPC.
#   - Broad, wildcarded instance IAM policy.
#   - No KMS CMK, no Secrets Manager (plaintext DB creds via user-data).
#   - No WAF, no VPC endpoints, no deny NACLs.
# ===========================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge({
      Project     = "zt-dissertation"
      Environment = "A-baseline"
      Model       = "perimeter"
      ManagedBy   = "terraform"
    }, var.tags)
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Random DB password (still stored in plaintext user-data — the baseline weakness).
resource "random_password" "db" {
  length  = 20
  special = false
}

# Django SECRET_KEY — generated fresh, but injected as plaintext (baseline weakness).
resource "random_password" "secret_key" {
  length  = 50
  special = false
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, length(var.public_subnet_cidrs))
  zero_trust = false
}

# ---------------------------------------------------------------------------
# App artifact — package Logi-Track and publish to a private S3 bucket (SSE-S3).
# Instances pull it at boot via the broad baseline role.
# ---------------------------------------------------------------------------
module "app_artifact" {
  source = "../../modules/app_artifact"

  name_prefix    = var.name_prefix
  app_source_dir = "${path.root}/../../../app/logi-track"
}

module "networking" {
  source = "../../modules/networking"

  name_prefix          = var.name_prefix
  vpc_cidr             = var.vpc_cidr
  azs                  = local.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  zero_trust           = local.zero_trust
  enable_nat           = false # baseline runs workloads in public subnets
  enable_vpc_endpoints = false
}

module "security" {
  source = "../../modules/security"

  name_prefix = var.name_prefix
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = module.networking.vpc_cidr
  zero_trust  = local.zero_trust
  admin_cidr  = var.admin_cidr
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = var.name_prefix
  zero_trust  = local.zero_trust # broad policy
}

module "database" {
  source = "../../modules/database"

  name_prefix         = var.name_prefix
  subnet_ids          = module.networking.public_subnet_ids # exposed, by design
  db_sg_id            = module.security.db_sg_id
  db_name             = var.db_name
  db_username         = var.db_username
  db_password         = random_password.db.result
  instance_class      = var.db_instance_class
  publicly_accessible = true  # baseline exposes the DB
  storage_encrypted   = false # baseline: no encryption at rest
}

module "wazuh" {
  source = "../../modules/wazuh"
  count  = var.deploy_wazuh ? 1 : 0

  name_prefix = var.name_prefix
  vpc_id      = module.networking.vpc_id
  subnet_id   = module.networking.public_subnet_ids[0]
  vpc_cidr    = module.networking.vpc_cidr
  admin_cidr  = var.admin_cidr
  key_name    = var.key_name
  # No trail bucket in Environment A: no CloudTrail (Table 3.1), so the wodle and AWS
  # rules stay off and MTTD reports zero detection coverage by design.
}

module "compute" {
  source = "../../modules/compute"

  name_prefix           = var.name_prefix
  zero_trust            = local.zero_trust
  vpc_id                = module.networking.vpc_id
  alb_subnet_ids        = module.networking.public_subnet_ids
  app_subnet_ids        = module.networking.public_subnet_ids # app in public subnets
  alb_sg_id             = module.security.alb_sg_id
  app_sg_id             = module.security.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  key_name              = var.key_name
  ebs_encrypted         = false

  # Baseline: plaintext DB + app creds injected via user-data (no Secrets Manager).
  db_host             = module.database.db_address
  db_name             = module.database.db_name
  db_username         = var.db_username
  db_password         = random_password.db.result
  secret_key          = random_password.secret_key.result
  email_host_user     = var.email_host_user
  email_host_password = var.email_host_password
  default_from_email  = var.default_from_email
  aws_region          = var.aws_region

  # App artifact pulled from S3 at boot.
  app_artifact_bucket = module.app_artifact.bucket
  app_artifact_key    = module.app_artifact.object_key

  wazuh_manager_ip = var.deploy_wazuh ? module.wazuh[0].manager_private_ip : ""
}
