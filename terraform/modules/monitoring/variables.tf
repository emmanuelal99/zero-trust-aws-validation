variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC whose traffic is captured by VPC Flow Logs."
  type        = string
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention for VPC Flow Logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
