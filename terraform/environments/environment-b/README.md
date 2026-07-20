# Environment B — Zero Trust

The same shared modules as Environment A, configured with `zero_trust = true`. A and B
differ only by configuration, giving a controlled-variable comparison for the dissertation.

## Controls (all zero_trust toggles flipped on)

- **Network segmentation:** app + DB + Wazuh in private subnets across two AZs; only the
  ALB and NAT gateway sit in public subnets. Interface/gateway VPC endpoints (SSM,
  ssmmessages, ec2messages, Secrets Manager, KMS, logs, S3) keep AWS-API traffic private.
  Deny-by-default private NACLs.
- **SG micro-segmentation:** internet -> ALB SG -> app SG -> DB SG. No public app port,
  no inbound SSH, restricted egress.
- **Identity & least privilege:** scoped instance IAM role (no wildcards) — secret read +
  KMS decrypt (both resource-scoped) + logs. Access via SSM Session Manager only (no key
  pair, no port 22).
- **Encryption & secrets:** customer-managed KMS CMK encrypts EBS + RDS at rest; DB
  credentials live in Secrets Manager and are pulled at boot via the instance role; IMDSv2
  required.
- **Ingress (edge module):** WAFv2 (AWS managed rule sets) fronts the ALB. Identity-aware
  access via Cognito OIDC is scaffolded behind `identity_aware_auth` but **OFF by default**
  — the dissertation runs WAF-only at the edge for now. Flip `identity_aware_auth = true`
  (and set `cognito_callback_urls`) to provision a Cognito user pool + hosted UI and an
  `authenticate-cognito` listener rule without reworking the module.

## Usage

```bash
cd terraform/environments/environment-b
cp terraform.tfvars.example terraform.tfvars   # narrow admin_cidr
terraform init
terraform plan
```

Region is `eu-west-2`; compute is spread across two AZs (`public_subnet_cidrs` /
`private_subnet_cidrs` each define one subnet per AZ).
