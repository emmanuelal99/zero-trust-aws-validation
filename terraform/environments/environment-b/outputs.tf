output "alb_dns_name" {
  description = "Public endpoint of the Logi-Track app — target for Nuclei."
  value       = module.compute.alb_dns_name
}

output "app_url" {
  description = "HTTP URL of the deployed app."
  value       = "http://${module.compute.alb_dns_name}"
}

output "db_endpoint" {
  description = "RDS endpoint (private)."
  value       = module.database.db_endpoint
}

output "vpc_id" {
  description = "VPC ID for this environment."
  value       = module.networking.vpc_id
}

output "kms_key_arn" {
  description = "Customer-managed KMS key ARN."
  value       = module.kms.key_arn
}

output "db_secret_arn" {
  description = "Secrets Manager ARN holding the DB credentials."
  value       = module.secrets.secret_arn
}

output "web_acl_arn" {
  description = "WAFv2 web ACL ARN fronting the ALB."
  value       = module.edge.web_acl_arn
}

output "identity_aware_auth_enabled" {
  description = "Whether Cognito OIDC is active at the edge."
  value       = var.identity_aware_auth
}

output "wazuh_manager_private_ip" {
  description = "Wazuh manager private IP (reach the dashboard via SSM port-forward)."
  value       = var.deploy_wazuh ? module.wazuh[0].manager_private_ip : null
}
