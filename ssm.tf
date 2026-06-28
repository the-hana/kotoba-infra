# JWT シークレットと Gemini API キーを SSM Parameter Store に保存
# DB URL → rds.tf で管理
# CloudFront distribution ID → cloudfront.tf (PR 4) で追加予定

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/kotoba-ai/jwt_secret"
  type  = "SecureString"
  value = var.jwt_secret

  tags = local.common_tags
}

resource "aws_ssm_parameter" "gemini_api_key" {
  name  = "/kotoba-ai/gemini_api_key"
  type  = "SecureString"
  value = var.gemini_api_key

  tags = local.common_tags
}

resource "aws_ssm_parameter" "rails_master_key" {
  name  = "/kotoba-ai/rails_master_key"
  type  = "SecureString"
  value = var.rails_master_key

  tags = local.common_tags
}

resource "aws_ssm_parameter" "internal_api_key" {
  name  = "/kotoba-ai/internal_api_key"
  type  = "SecureString"
  value = var.internal_api_key

  tags = local.common_tags
}
