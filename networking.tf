# ──────────────────────────────────────────
# VPC
# ──────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "kotoba-vpc" })
}

# ──────────────────────────────────────────
# Public Subnet ×2
# RDS DB Subnet Group は最低2AZ 必要なため2サブネット用意
# ──────────────────────────────────────────
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = local.az_a
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "kotoba-public-a" })
}

resource "aws_subnet" "public_c" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = local.az_c
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "kotoba-public-c" })
}

# ──────────────────────────────────────────
# Internet Gateway + Route Table
# NAT Gateway なし — Public Subnet + SG で接続制御
# ──────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "kotoba-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "kotoba-rtb-public" })
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_c" {
  subnet_id      = aws_subnet.public_c.id
  route_table_id = aws_route_table.public.id
}

# ──────────────────────────────────────────
# Security Group: ECS (Rails API)
# CloudFront → EC2 へのポート 3000 のみ許可
# ──────────────────────────────────────────
resource "aws_security_group" "ecs" {
  name        = "kotoba-ecs"
  description = "ECS Rails API"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Rails API from CloudFront"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "kotoba-ecs" })
}

# ──────────────────────────────────────────
# Security Group: RDS
# ECS SG からのみ PostgreSQL 5432 を許可
# ──────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "kotoba-rds"
  description = "RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.common_tags, { Name = "kotoba-rds" })
}
