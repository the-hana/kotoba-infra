# ──────────────────────────────────────────
# AWS Budgets — 月次コストアラート
# CloudWatch 請求アラートは us-east-1 専用のため Budgets を使用 (リージョン非依存)
# Starter プラン: $200 クレジット / 6ヶ月 → 月あたり約 $33 が上限目安
# ──────────────────────────────────────────
resource "aws_budgets_budget" "monthly" {
  name         = "kotoba-ai-monthly"
  budget_type  = "COST"
  limit_amount = "33"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # クレジット適用後の純コストは $0 になりアラートが発火しないため、クレジットを除外して実消費量を追跡する
  cost_types {
    include_credit = false
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
