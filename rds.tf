# ──────────────────────────────────────────
# DB Subnet Group
# RDS は最低 2AZ のサブネットグループが必要
# ──────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "kotoba-rds-subnet-group"
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_c.id]

  tags = merge(local.common_tags, { Name = "kotoba-rds-subnet-group" })
}

# ──────────────────────────────────────────
# RDS PostgreSQL
# db.t3.micro / Free Tier 最適化
# publicly_accessible=false: NAT Gateway 不要 + セキュリティ向上
# ──────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier        = "kotoba-rds"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_type = "gp3"

  publicly_accessible          = false
  multi_az                     = false
  skip_final_snapshot          = true
  deletion_protection          = false
  backup_retention_period      = 0
  performance_insights_enabled = false

  lifecycle {
    ignore_changes = [password]
  }

  tags = merge(local.common_tags, { Name = "kotoba-rds" })
}

# ──────────────────────────────────────────
# SSM: DATABASE_URL
# ECS Task から secrets injection で参照
# urlencode でパスワードの特殊文字をエスケープ
# ──────────────────────────────────────────
resource "aws_ssm_parameter" "database_url" {
  name  = "/kotoba-ai/database_url"
  type  = "SecureString"
  value = "postgres://${urlencode(var.db_username)}:${urlencode(var.db_password)}@${aws_db_instance.main.address}:5432/${var.db_name}"

  tags = local.common_tags
}
