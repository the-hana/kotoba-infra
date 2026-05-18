# ──────────────────────────────────────────
# S3 Bucket: kotoba-web 静的ホスティング
# パブリックアクセス全ブロック + OAC 経由のみ許可
# ──────────────────────────────────────────
resource "aws_s3_bucket" "frontend" {
  bucket = "kotoba-web-${local.env}"

  tags = merge(local.common_tags, { Name = "kotoba-web-${local.env}" })
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────
# S3 Bucket Policy
# CloudFront distribution からの s3:GetObject のみ許可
# ──────────────────────────────────────────
data "aws_iam_policy_document" "s3_frontend" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.s3_frontend.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}
