terraform {
  required_version = "~> 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Terraform Remote State 用 S3 バケット
resource "aws_s3_bucket" "tfstate" {
  bucket = var.tfstate_bucket_name

  # 誤って destroy しても State が消えないよう保護
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    project = "kotoba-ai"
    env     = "prod"
    purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 古い State バージョンの自動削除（Free Tier 容量節約）
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# State Lock 用 DynamoDB テーブル
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = var.tfstate_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # 誤って destroy しても Lock テーブルが消えないよう保護
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    project = "kotoba-ai"
    env     = "prod"
    purpose = "terraform-state-lock"
  }
}
