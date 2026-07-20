variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "create" {
  description = "Whether to create a customer-managed KMS key. Env B (Zero Trust) sets true; Env A relies on AWS-managed default keys."
  type        = bool
  default     = false
}

variable "description" {
  description = "Key description."
  type        = string
  default     = "Customer-managed key for the environment"
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
