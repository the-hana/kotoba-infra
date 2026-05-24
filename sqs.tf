# ──────────────────────────────────────────
# SQS: daily_story キュー + DLQ
# EventBridge → SQS → Lambda daily_story の順で処理
# MaxReceiveCount=3 で 3 回失敗したメッセージは DLQ へ
# ──────────────────────────────────────────

# DLQ (Dead Letter Queue)
resource "aws_sqs_queue" "daily_story_dlq" {
  name                      = "kotoba-daily-story-dlq"
  message_retention_seconds = 1209600 # 14日間保持してデバッグ可能に

  tags = local.common_tags
}

# メインキュー
resource "aws_sqs_queue" "daily_story" {
  name                      = "kotoba-daily-story"
  visibility_timeout_seconds = 180 # Lambda timeout(30s) × 6 (AWS 推奨値)
  message_retention_seconds = 86400

  tags = local.common_tags
}

# Redrive policy: 3 回失敗 → DLQ (provider v5 は独立リソース)
resource "aws_sqs_queue_redrive_policy" "daily_story" {
  queue_url = aws_sqs_queue.daily_story.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.daily_story_dlq.arn
    maxReceiveCount     = 3
  })
}

# DLQ 側: メインキューからの転送を許可
resource "aws_sqs_queue_redrive_allow_policy" "daily_story_dlq" {
  queue_url = aws_sqs_queue.daily_story_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.daily_story.arn]
  })
}

# ──────────────────────────────────────────
# SQS Queue Policy
# EventBridge がメインキューへメッセージを送信する権限
# ──────────────────────────────────────────
data "aws_iam_policy_document" "sqs_eventbridge" {
  statement {
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.daily_story.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.daily_story_trigger.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "daily_story" {
  queue_url = aws_sqs_queue.daily_story.id
  policy    = data.aws_iam_policy_document.sqs_eventbridge.json
}
