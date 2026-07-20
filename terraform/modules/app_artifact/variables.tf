variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "app_source_dir" {
  description = "Absolute or root-relative path to the Logi-Track app source directory to package."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key ARN for artifact encryption (Zero Trust). Null uses SSE-S3 (AES256)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
