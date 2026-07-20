variable "name_prefix" {
  description = "Prefix for all resource names (e.g. env-a, env-b)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (one per AZ)."
  type        = list(string)
}

variable "zero_trust" {
  description = "When true, apply Zero Trust networking (private-only workloads, VPC endpoints, deny-by-default NACLs)."
  type        = bool
  default     = false
}

variable "enable_nat" {
  description = "Create a NAT gateway so private subnets have egress. Required for Env B (private app subnets) egress to AWS APIs not covered by endpoints."
  type        = bool
  default     = false
}

variable "enable_vpc_endpoints" {
  description = "Create interface/gateway VPC endpoints (SSM, Secrets Manager, KMS, S3). Zero Trust: keeps traffic to AWS APIs off the public internet."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}
