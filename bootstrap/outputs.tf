output "tfstate_bucket_name" {
  description = "Terraform state 用 S3 バケット名"
  value       = aws_s3_bucket.tfstate.bucket
}

output "tfstate_lock_table_name" {
  description = "State lock 用 DynamoDB テーブル名"
  value       = aws_dynamodb_table.tfstate_lock.name
}
