variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "zero_trust" {
  description = "Toggles ZT-specific behaviour: fetch DB creds from Secrets Manager, no SSH key, encrypted EBS."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Public subnets for the internet-facing ALB."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Subnets for the app instances. Baseline: public. Zero Trust: private."
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group for the ALB."
  type        = string
}

variable "app_sg_id" {
  description = "Security group for the app instances."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile to attach."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID. Null resolves to the latest Amazon Linux 2023."
  type        = string
  default     = null
}

variable "app_port" {
  description = "Port the Django app listens on."
  type        = number
  default     = 8000
}

variable "key_name" {
  description = "EC2 key pair name for SSH (baseline only). Null under Zero Trust (SSM only)."
  type        = string
  default     = null
}

variable "ebs_encrypted" {
  description = "Encrypt the root EBS volume. Baseline false, Zero Trust true."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key for EBS encryption (Zero Trust). Null uses the AWS-managed key."
  type        = string
  default     = null
}

# --- Database wiring -------------------------------------------------------
variable "db_host" {
  description = "Database host."
  type        = string
}

variable "db_name" {
  description = "Database name."
  type        = string
}

variable "db_username" {
  description = "Database username (baseline plaintext injection)."
  type        = string
  default     = ""
}

variable "db_password" {
  description = "Database password (baseline plaintext injection)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for app creds (Zero Trust): DB + SECRET_KEY + email. Fetched at boot via the instance role."
  type        = string
  default     = ""
}

# --- Application secrets (baseline plaintext injection) --------------------
variable "secret_key" {
  description = "Django SECRET_KEY (baseline plaintext injection). Zero Trust reads it from the secret instead."
  type        = string
  default     = ""
  sensitive   = true
}

variable "email_host_user" {
  description = "SMTP username (baseline plaintext). Email disabled by design; blank by default."
  type        = string
  default     = ""
}

variable "email_host_password" {
  description = "SMTP password (baseline plaintext). Email disabled by design; blank by default."
  type        = string
  default     = ""
  sensitive   = true
}

variable "default_from_email" {
  description = "Default from-address (baseline plaintext). Email disabled by design; blank by default."
  type        = string
  default     = ""
}

# --- Application artifact ---------------------------------------------------
variable "app_artifact_bucket" {
  description = "S3 bucket holding the packaged Logi-Track app zip, pulled at boot."
  type        = string
}

variable "app_artifact_key" {
  description = "S3 key of the packaged Logi-Track app zip."
  type        = string
}

variable "aws_region" {
  description = "AWS region (used by user-data to reach Secrets Manager)."
  type        = string
}

# --- Monitoring ------------------------------------------------------------
variable "wazuh_manager_ip" {
  description = "Wazuh manager private IP for agent enrolment. Empty skips agent install."
  type        = string
  default     = ""
}

# --- Scaling ---------------------------------------------------------------
variable "min_size" {
  description = "ASG minimum size."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG maximum size."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "ASG desired capacity."
  type        = number
  default     = 1
}

variable "health_check_grace_period" {
  description = "Seconds the ASG ignores ELB health checks after launch. Raise for Zero Trust (Env B) slower boots so a not-yet-healthy instance survives long enough to SSM in and read the bootstrap log."
  type        = number
  default     = 300
}

variable "wait_for_capacity_timeout" {
  description = "How long Terraform waits for a healthy instance before failing the apply. Raise for Env B (slower ZT boot). Set to \"0\" to skip waiting entirely."
  type        = string
  default     = "10m"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
