variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "tfstate_bucket_name" {
  description = "Terraform state 保存用 S3 バケット名"
  type        = string
  default     = "kotoba-ai-tfstate"
}

variable "tfstate_lock_table_name" {
  description = "Terraform state lock 用 DynamoDB テーブル名"
  type        = string
  default     = "kotoba-ai-tfstate-lock"
}
