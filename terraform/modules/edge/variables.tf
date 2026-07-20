variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

# --- WAF -------------------------------------------------------------------
variable "enable_waf" {
  description = "Create and associate a WAFv2 web ACL with the ALB. Env B (Zero Trust) sets true."
  type        = bool
  default     = false
}

variable "alb_arn" {
  description = "ARN of the ALB to associate the web ACL with."
  type        = string
  default     = ""
}

# --- Identity-aware access (Cognito OIDC) ----------------------------------
variable "identity_aware_auth" {
  description = "Enable Cognito OIDC at the edge via an authenticate-cognito ALB listener rule. OFF by default; WAF-only for now."
  type        = bool
  default     = false
}

variable "listener_arn" {
  description = "ARN of the ALB HTTP(S) listener to attach the Cognito auth rule to. Only used when identity_aware_auth = true."
  type        = string
  default     = ""
}

variable "target_group_arn" {
  description = "ARN of the app target group to forward to after authentication. Only used when identity_aware_auth = true."
  type        = string
  default     = ""
}

variable "cognito_domain_prefix" {
  description = "Prefix for the Cognito hosted-UI domain. Empty derives from name_prefix. Only used when identity_aware_auth = true."
  type        = string
  default     = ""
}

variable "cognito_callback_urls" {
  description = "OIDC callback URLs for the user pool client (typically https://<alb-dns>/oauth2/idpresponse). Only used when identity_aware_auth = true."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
