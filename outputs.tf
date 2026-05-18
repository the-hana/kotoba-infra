# ──────────────────────────────────────────
# Outputs
# PR 4: CloudFront + S3 フロントエンド関連
# PR 6: ECR / ECS / RDS / IAM outputs 追加予定
# ──────────────────────────────────────────
output "cloudfront_domain_name" {
  description = "CloudFront distribution domain (frontend URL)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (GitHub Actions cache invalidation)"
  value       = aws_cloudfront_distribution.main.id
}

output "s3_frontend_bucket" {
  description = "S3 bucket name for kotoba-web (GitHub Actions S3 sync target)"
  value       = aws_s3_bucket.frontend.id
}
