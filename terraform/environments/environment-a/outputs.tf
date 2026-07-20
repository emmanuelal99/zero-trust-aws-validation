output "alb_dns_name" {
  description = "Public endpoint of the Logi-Track app — target for Nuclei."
  value       = module.compute.alb_dns_name
}

output "app_url" {
  description = "HTTP URL of the deployed app."
  value       = "http://${module.compute.alb_dns_name}"
}

output "db_endpoint" {
  description = "RDS endpoint."
  value       = module.database.db_endpoint
}

output "vpc_id" {
  description = "VPC ID for this environment."
  value       = module.networking.vpc_id
}

output "wazuh_manager_private_ip" {
  description = "Wazuh manager private IP (if deployed)."
  value       = var.deploy_wazuh ? module.wazuh[0].manager_private_ip : null
}

output "wazuh_dashboard_url" {
  description = "Wazuh dashboard URL (if deployed and in a public subnet)."
  value       = var.deploy_wazuh ? "https://${module.wazuh[0].manager_public_ip}" : null
}
