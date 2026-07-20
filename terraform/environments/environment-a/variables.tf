variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "eu-west-2"
}

variable "name_prefix" {
  description = "Resource name prefix for this environment."
  type        = string
  default     = "env-a"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.10.0.0/24", "10.10.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ)."
  type        = list(string)
  default     = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "admin_cidr" {
  description = "CIDR permitted SSH/admin access. Broad by design in the baseline."
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access (baseline). Set to an existing key or null."
  type        = string
  default     = null
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

# --- Email (disabled by design; injected as plaintext — the baseline contrast) ---
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

variable "tags" {
  description = "Extra tags for all resources."
  type        = map(string)
  default     = {}
}
