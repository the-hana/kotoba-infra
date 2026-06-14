# ──────────────────────────────────────────
# CloudFront Origin Access Control (OAC)
# OAI より権限が精細、署名ベースで S3 接続を保護
# S3 バケットポリシーの aws:SourceArn 条件と対になるリソース
# ──────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "kotoba-web-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ──────────────────────────────────────────
# Managed Cache / Origin Request Policy lookups
# ハードコード UUID より可読性が高く、AWS がポリシーを更新した場合にも追従しやすい
# ──────────────────────────────────────────
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ──────────────────────────────────────────
# CloudFront Distribution
#
# Origin 構成:
#   s3-frontend  : kotoba-web S3 バケット (OAC)
#   ec2-api      : ECS on EC2 Rails API (HTTP:3000)
#
# Cache Behavior:
#   /*           → S3 (React SPA, CachingOptimized)
#   /api/*       → EC2 (CachingDisabled, AllViewerExceptHostHeader)
#   /webhooks/*  → EC2 (CachingDisabled, AllViewerExceptHostHeader)
#
# EC2 public_ip は Elastic IP 未使用のため EC2 再起動で変わる。
# 初期値のみ Terraform で設定し、以降は PR 5 の Lambda(cf_origin_updater) が更新する。
# ──────────────────────────────────────────
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  comment             = "kotoba-ai frontend + API proxy"

  # ── Origin 1: S3 (OAC) ──────────────────
  origin {
    origin_id                = "s3-frontend"
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ── Origin 2: EC2 Rails API ──────────────
  origin {
    origin_id   = "ec2-api"
    domain_name = aws_instance.ecs.public_dns

    custom_origin_config {
      http_port              = 3000
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── Default: S3 (React SPA) ──────────────
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # ── /api/* → EC2 ─────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ec2-api"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
  }

  # ── /webhooks/* → EC2 ────────────────────
  ordered_cache_behavior {
    path_pattern           = "/webhooks/*"
    target_origin_id       = "ec2-api"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
  }

  # ── SPA React Router: 404/403 → index.html ──
  # S3 が存在しないパスに 403 を返すケースも index.html に統一
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # Lambda(cf_origin_updater) が EC2 再起動時に origin を API で直接更新するため、
  # terraform apply で初期 IP に戻されないよう ignore する
  lifecycle {
    ignore_changes = [origin]
  }

  tags = local.common_tags
}

# ──────────────────────────────────────────
# SSM: CloudFront Distribution ID
# PR 5 の Lambda(cf_origin_updater) が読み込んで origin を更新する
# ──────────────────────────────────────────
resource "aws_ssm_parameter" "cf_distribution_id" {
  name  = "/kotoba-ai/cf_distribution_id"
  type  = "String"
  value = aws_cloudfront_distribution.main.id

  tags = local.common_tags
}
