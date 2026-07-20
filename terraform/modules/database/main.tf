# RDS PostgreSQL. Encryption, exposure and subnet placement are the toggles that separate
# the baseline from the Zero Trust model.

locals {
  tags = merge(var.tags, { Component = "database" })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db-subnets"
  subnet_ids = var.subnet_ids
  tags       = merge(local.tags, { Name = "${var.name_prefix}-db-subnets" })
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.storage_encrypted ? var.kms_key_arn : null

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = var.publicly_accessible

  multi_az                   = false
  skip_final_snapshot        = true
  deletion_protection        = false
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  tags = merge(local.tags, { Name = "${var.name_prefix}-db" })
}
