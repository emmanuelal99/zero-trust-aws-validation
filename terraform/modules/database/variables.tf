variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. Baseline may place these in public subnets; Zero Trust uses private subnets."
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group ID for the database."
  type        = string
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "logitrack"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "logitrack"
}

variable "db_password" {
  description = "Master password."
  type        = string
  sensitive   = true
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.14"
}

variable "allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

variable "publicly_accessible" {
  description = "Whether the DB is publicly accessible. Baseline true (exposed), Zero Trust false."
  type        = bool
  default     = false
}

variable "storage_encrypted" {
  description = "Encrypt storage at rest. Baseline false (defaults), Zero Trust true with a CMK."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "KMS key ARN for storage encryption (Zero Trust). Null uses the AWS-managed key when storage_encrypted is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
