variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which to create the security groups."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — used by the baseline model for flat internal trust."
  type        = string
}

variable "zero_trust" {
  description = "When true, use SG-to-SG micro-segmentation and drop SSH. When false, use the flat perimeter baseline."
  type        = bool
  default     = false
}

variable "app_port" {
  description = "Port the Django app listens on."
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "admin_cidr" {
  description = "CIDR permitted SSH access in the baseline model (broad by design for Env A). Ignored under Zero Trust."
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
