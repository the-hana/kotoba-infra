variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "db_password" {
  description = "RDS PostgreSQL パスワード (16文字以上推奨)"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "Rails JWT 署名キー (64文字以上推奨)"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Gemini API キー"
  type        = string
  sensitive   = true
}

variable "alert_email" {
  description = "CloudWatch Alarm 通知先メールアドレス"
  type        = string
}

variable "github_org" {
  description = "GitHub ユーザー名 / Organization 名"
  type        = string
  default     = "butahana"
}

variable "db_name" {
  description = "RDS PostgreSQL データベース名"
  type        = string
  default     = "kotoba_production"
}

variable "db_username" {
  description = "RDS PostgreSQL ユーザー名"
  type        = string
  default     = "kotoba"
}
