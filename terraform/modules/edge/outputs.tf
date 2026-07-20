output "web_acl_arn" {
  description = "ARN of the WAFv2 web ACL, or null when not created."
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].arn : null
}

output "cognito_user_pool_id" {
  description = "Cognito user pool ID, or null when identity-aware auth is disabled."
  value       = var.identity_aware_auth ? aws_cognito_user_pool.this[0].id : null
}

output "cognito_user_pool_arn" {
  description = "Cognito user pool ARN, or null when identity-aware auth is disabled."
  value       = var.identity_aware_auth ? aws_cognito_user_pool.this[0].arn : null
}

output "cognito_domain" {
  description = "Cognito hosted-UI domain, or null when identity-aware auth is disabled."
  value       = var.identity_aware_auth ? aws_cognito_user_pool_domain.this[0].domain : null
}
