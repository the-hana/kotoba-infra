#!/bin/bash
# terraform apply 後に実行 — GitHub Secrets を terraform output で自動更新
#
# 【再デプロイ手順 (アカウント解約後の新規アカウントで実行)】
#
# 1. bootstrap/terraform.tfvars の tfstate_bucket_name suffix を新 Account ID 下6桁に変更
#    例: kotoba-ai-tfstate-XXXXXX → kotoba-ai-tfstate-123456
#
# 2. backend.tf の bucket も同じ名前に変更
#    例: kotoba-ai-tfstate-XXXXXX → kotoba-ai-tfstate-123456
#
# 3. cd bootstrap && terraform init && terraform apply
#
# 4. cd .. && terraform init && terraform plan && terraform apply
#
# 5. bash scripts/setup.sh   ← このスクリプト
#
# 6. kotoba-api main に push → ECR build → ECS deploy 確認
#    kotoba-web main に push → S3 sync → CloudFront 確認
#
# 7. rails db:migrate db:seed (ECS Exec で実行)

set -e

# ── 事前チェック ───────────────────────────────────────────
if ! command -v gh &> /dev/null; then
  echo "Error: gh CLI が必要です。brew install gh でインストールしてください。"
  exit 1
fi

if ! terraform output github_actions_role_arn &> /dev/null 2>&1; then
  echo "Error: terraform output が取得できません。kotoba-infra/ で terraform apply が完了しているか確認してください。"
  exit 1
fi

# ── terraform output 取得 ──────────────────────────────────
ROLE_ARN=$(terraform output -raw github_actions_role_arn)
S3_BUCKET=$(terraform output -raw s3_frontend_bucket)
CF_ID=$(terraform output -raw cloudfront_distribution_id)
CF_DOMAIN=$(terraform output -raw cloudfront_domain_name)

echo "取得した値:"
echo "  AWS_ROLE_ARN:       $ROLE_ARN"
echo "  S3_BUCKET:          $S3_BUCKET"
echo "  CF_DISTRIBUTION_ID: $CF_ID"
echo "  VITE_API_BASE_URL:  https://$CF_DOMAIN"
echo ""

# ── GitHub Secrets 更新 ────────────────────────────────────
gh secret set AWS_ROLE_ARN       --body "$ROLE_ARN"          --repo the-hana/kotoba-api
gh secret set AWS_ROLE_ARN       --body "$ROLE_ARN"          --repo the-hana/kotoba-web
gh secret set S3_BUCKET          --body "$S3_BUCKET"         --repo the-hana/kotoba-web
gh secret set CF_DISTRIBUTION_ID --body "$CF_ID"             --repo the-hana/kotoba-web
gh secret set VITE_API_BASE_URL  --body "https://$CF_DOMAIN" --repo the-hana/kotoba-web

echo "GitHub Secrets の更新が完了しました。"
