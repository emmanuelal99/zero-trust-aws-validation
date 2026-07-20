variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "name_prefix" {
  description = "Resource name prefix for this environment."
  type        = string
  default     = "env-b"
}

variable "vpc_cidr" {
  description = "VPC CIDR. Distinct from Env A so both can coexist in one account."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ) — host only the ALB and NAT under Zero Trust."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ) — host the app, DB and Wazuh under Zero Trust."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "admin_cidr" {
  description = "CIDR permitted to reach the Wazuh dashboard (443). Narrow this to your IP; there is no public SSH under Zero Trust."
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "App instance type."
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "logitrack"
}

variable "db_username" {
  description = "Database master username."
  type        = string
  default     = "logitrack"
}

variable "deploy_wazuh" {
  description = "Whether to deploy a Wazuh manager in this environment."
  type        = bool
  default     = true
}

# --- Email (disabled by design; stored in the secret for the ZT contrast) ---
variable "email_host_user" {
  description = "SMTP username. Email is disabled for security testing; leave blank."
  type        = string
  default     = ""
}

variable "email_host_password" {
  description = "SMTP password. Email is disabled for security testing; leave blank."
  type        = string
  default     = ""
  sensitive   = true
}

variable "default_from_email" {
  description = "Default from-address. Email is disabled for security testing; leave blank."
  type        = string
  default     = ""
}

# --- Edge / identity-aware access ------------------------------------------
variable "identity_aware_auth" {
  description = "Enable Cognito OIDC at the edge. OFF by default — the dissertation runs WAF-only at the edge for now."
  type        = bool
  default     = false
}

variable "cognito_callback_urls" {
  description = "OIDC callback URLs for the Cognito client. Only used when identity_aware_auth = true."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Extra tags for all resources."
  type        = map(string)
  default     = {}
}
