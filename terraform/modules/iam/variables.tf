variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "zero_trust" {
  description = "When true, attach a least-privilege scoped policy. When false, attach a broad (over-permissioned) policy modelling the baseline."
  type        = bool
  default     = false
}

variable "secret_arns" {
  description = "Secret ARNs the instance may read under Zero Trust (scoped GetSecretValue)."
  type        = list(string)
  default     = []
}

variable "kms_key_arns" {
  description = "KMS key ARNs the instance may use under Zero Trust (scoped Decrypt)."
  type        = list(string)
  default     = []
}

variable "artifact_bucket_arn" {
  description = "S3 bucket ARN holding the app artifact the instance may read under Zero Trust (scoped GetObject). Empty disables the statement."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
