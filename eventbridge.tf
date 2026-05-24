# ──────────────────────────────────────────
# EventBridge Rules × 5
#
# 1. kotoba-daily-story-trigger  cron UTC 15:00 (JST 00:00) → SQS
# 2. kotoba-rds-auto-stop        RDS-EVENT-0088 (DB起動)    → Lambda rds_stop
# 3. kotoba-ec2-auto-stop        cron UTC 18:00 (JST 03:00) → Lambda ec2_stop
# 4. kotoba-ec2-auto-start       cron UTC 00:00 (JST 09:00) → Lambda ec2_start
# 5. kotoba-cf-origin-update     EC2 state=running          → Lambda cf_origin_updater
# ──────────────────────────────────────────

# ── 1. Daily story trigger ───────────────
resource "aws_cloudwatch_event_rule" "daily_story_trigger" {
  name                = "kotoba-daily-story-trigger"
  schedule_expression = "cron(0 15 * * ? *)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "daily_story_sqs" {
  rule = aws_cloudwatch_event_rule.daily_story_trigger.name
  arn  = aws_sqs_queue.daily_story.arn
}

# ── 2. RDS 自動再起動を検知して即停止 ────
# AWS は停止中の RDS を 7 日後に自動起動する。
# RDS-EVENT-0088 (DB instance started) を受けて Lambda が再度停止する。
resource "aws_cloudwatch_event_rule" "rds_auto_stop" {
  name = "kotoba-rds-auto-stop"

  event_pattern = jsonencode({
    source        = ["aws.rds"]
    "detail-type" = ["RDS DB Instance Event"]
    detail = {
      EventId          = ["RDS-EVENT-0088"]
      SourceIdentifier = [aws_db_instance.main.identifier]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "rds_auto_stop_lambda" {
  rule = aws_cloudwatch_event_rule.rds_auto_stop.name
  arn  = aws_lambda_function.rds_stop.arn
}

resource "aws_lambda_permission" "rds_auto_stop" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_auto_stop.arn
}

# ── 3. ECS 停止 (JST 03:00) ──────────────
resource "aws_cloudwatch_event_rule" "ec2_auto_stop" {
  name                = "kotoba-ec2-auto-stop"
  schedule_expression = "cron(0 18 * * ? *)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "ec2_auto_stop_lambda" {
  rule = aws_cloudwatch_event_rule.ec2_auto_stop.name
  arn  = aws_lambda_function.ec2_stop.arn
}

resource "aws_lambda_permission" "ec2_auto_stop" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_auto_stop.arn
}

# ── 4. ECS 起動 (JST 09:00) ──────────────
resource "aws_cloudwatch_event_rule" "ec2_auto_start" {
  name                = "kotoba-ec2-auto-start"
  schedule_expression = "cron(0 0 * * ? *)"
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "ec2_auto_start_lambda" {
  rule = aws_cloudwatch_event_rule.ec2_auto_start.name
  arn  = aws_lambda_function.ec2_start.arn
}

resource "aws_lambda_permission" "ec2_auto_start" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_start.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_auto_start.arn
}

# ── 5. EC2 起動 → CloudFront origin 更新 ─
# EC2 が running 状態になったタイミングで新しいパブリック IP を CF に反映する
resource "aws_cloudwatch_event_rule" "cf_origin_update" {
  name = "kotoba-cf-origin-update"

  event_pattern = jsonencode({
    source        = ["aws.ec2"]
    "detail-type" = ["EC2 Instance State-change Notification"]
    detail = {
      state = ["running"]
    }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "cf_origin_update_lambda" {
  rule = aws_cloudwatch_event_rule.cf_origin_update.name
  arn  = aws_lambda_function.cf_origin_updater.arn
}

resource "aws_lambda_permission" "cf_origin_update" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cf_origin_updater.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cf_origin_update.arn
}
