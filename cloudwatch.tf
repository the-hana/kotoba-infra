# ──────────────────────────────────────────
# SNS Topic + Email 通知
# DLQ アラームの送信先
# ──────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "kotoba-alerts"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "alert_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────────────
# CloudWatch Alarm: DLQ メッセージ数
# daily_story が 3 回失敗 → DLQ にメッセージが積まれたら通知
# ──────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "kotoba-daily-story-dlq-messages"
  alarm_description   = "DLQ にメッセージが届いた — daily_story Lambda の連続失敗を確認すること"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.daily_story_dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = local.common_tags
}
