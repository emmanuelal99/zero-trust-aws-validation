variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "create" {
  description = "Whether to store DB credentials in Secrets Manager. Env B (Zero Trust) sets true; Env A injects plaintext env vars instead."
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "KMS key ID/ARN to encrypt the secret. Null uses the AWS-managed key."
  type        = string
  default     = null
}

variable "db_username" {
  description = "Database username to store."
  type        = string
  default     = ""
}

variable "db_password" {
  description = "Database password to store."
  type        = string
  default     = ""
  sensitive   = true
}

variable "db_host" {
  description = "Database host to store."
  type        = string
  default     = ""
}

variable "db_name" {
  description = "Database name to store."
  type        = string
  default     = ""
}

variable "db_port" {
  description = "Database port to store."
  type        = number
  default     = 5432
}

variable "secret_key" {
  description = "Django SECRET_KEY to store (Zero Trust). Kept out of plaintext user-data."
  type        = string
  default     = ""
  sensitive   = true
}

variable "email_host_user" {
  description = "SMTP username to store. Email is disabled by design; blank by default."
  type        = string
  default     = ""
}

variable "email_host_password" {
  description = "SMTP password to store. Email is disabled by design; blank by default."
  type        = string
  default     = ""
  sensitive   = true
}

variable "default_from_email" {
  description = "Default from-address to store. Email is disabled by design; blank by default."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
