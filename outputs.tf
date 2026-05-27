# ──────────────────────────────────────────
# Outputs
# PR 4: CloudFront + S3 フロントエンド関連
# PR 6: ECR / ECS / IAM outputs 追加
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

output "ecr_repository_url" {
  description = "ECR リポジトリ URL (GitHub Actions docker push 対象)"
  value       = aws_ecr_repository.api.repository_url
}

output "ecs_cluster_name" {
  description = "ECS クラスター名 (GitHub Actions ECS 更新用)"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS サービス名 (GitHub Actions ECS 更新用)"
  value       = aws_ecs_service.api.name
}

output "github_actions_role_arn" {
  description = "GitHub Actions OIDC 用 IAM Role ARN (GitHub Secrets AWS_ROLE_ARN に設定)"
  value       = aws_iam_role.github_actions.arn
}
