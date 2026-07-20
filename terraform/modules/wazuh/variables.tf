variable "name_prefix" {
  description = "Prefix for all resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_id" {
  description = "Subnet in which to place the Wazuh manager."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR — agents in the VPC enrol with the manager."
  type        = string
}

variable "admin_cidr" {
  description = "CIDR permitted to reach the Wazuh dashboard (443) and SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "Instance type for the Wazuh manager (needs >= 4GB RAM). c7i-flex.large (4GB, x86_64) is free-tier eligible in eu-west-2 and matches Wazuh's recommended spec; t3.small (2GB) is the minimum fallback. Must be x86_64 to match the AL2023 AMI filter (NOT t4g/Graviton)."
  type        = string
  default     = "c7i-flex.large"
}

variable "ami_id" {
  description = "AMI ID. Null resolves to the latest Amazon Linux 2023."
  type        = string
  default     = null
}

variable "key_name" {
  description = "EC2 key pair for SSH access to the manager."
  type        = string
  default     = null
}

variable "aws_region" {
  description = "AWS region — passed to the Wazuh AWS-S3 wodle to scope CloudTrail polling."
  type        = string
  default     = "eu-west-2"
}

variable "trail_bucket_name" {
  description = "CloudTrail log bucket the wodle polls. Empty disables cloud detection (Env A)."
  type        = string
  default     = ""
}

variable "trail_bucket_arn" {
  description = "ARN of the CloudTrail log bucket for the scoped read policy. Empty in Env A."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags."
  type        = map(string)
  default     = {}
}
