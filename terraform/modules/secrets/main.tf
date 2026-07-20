# DB credentials in Secrets Manager (Zero Trust). Env A skips this (create = false) and
# injects plaintext credentials via user-data instead — the insecure baseline.

locals {
  tags = merge(var.tags, { Component = "secrets" })
}

resource "aws_secretsmanager_secret" "db" {
  count       = var.create ? 1 : 0
  name        = "${var.name_prefix}/app-credentials"
  description = "Logi-Track application credentials (DB + Django SECRET_KEY + email)"
  kms_key_id  = var.kms_key_id
  # Delete immediately on destroy (no 30-day recovery window) so repeated
  # apply/destroy cycles across the 30+ pipeline runs can recreate the secret
  # without hitting "scheduled for deletion" name collisions.
  recovery_window_in_days = 0
  tags                    = merge(local.tags, { Name = "${var.name_prefix}-app-credentials" })
}

resource "aws_secretsmanager_secret_version" "db" {
  count     = var.create ? 1 : 0
  secret_id = aws_secretsmanager_secret.db[0].id
  secret_string = jsonencode({
    username            = var.db_username
    password            = var.db_password
    host                = var.db_host
    dbname              = var.db_name
    port                = var.db_port
    secret_key          = var.secret_key
    email_host_user     = var.email_host_user
    email_host_password = var.email_host_password
    default_from_email  = var.default_from_email
  })
}
