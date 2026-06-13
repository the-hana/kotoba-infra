# ──────────────────────────────────────────
# EventBridge Rules × 5
#
# 1. kotoba-daily-story-trigger  cron UTC 10:10 (JST 19:10) → SQS   ★変更: サーバー起動10分後
# 2. kotoba-rds-auto-stop        RDS-EVENT-0088 (DB起動)    → Lambda rds_stop
# 3. kotoba-ec2-auto-stop        cron UTC 14:00 (JST 23:00) → Lambda ec2_stop  ★変更
# 4. kotoba-ec2-auto-start       cron UTC 10:00 (JST 19:00) → Lambda ec2_start ★変更
# 5. kotoba-cf-origin-update     EC2 state=running          → Lambda cf_origin_updater
# ──────────────────────────────────────────

# ── 1. Daily story trigger ───────────────
resource "aws_cloudwatch_event_rule" "daily_story_trigger" {
  name                = "kotoba-daily-story-trigger"
  schedule_expression = "cron(10 10 * * ? *)"  # JST 19:10 — サーバー起動(19:00)の10分後
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

# ── 3. EC2・RDS 停止 (JST 23:00) ─────────
resource "aws_cloudwatch_event_rule" "ec2_auto_stop" {
  name                = "kotoba-ec2-auto-stop"
  schedule_expression = "cron(0 14 * * ? *)"  # JST 23:00
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

# ── 4. EC2・RDS 起動 (JST 19:00) ─────────
resource "aws_cloudwatch_event_rule" "ec2_auto_start" {
  name                = "kotoba-ec2-auto-start"
  schedule_expression = "cron(0 10 * * ? *)"  # JST 19:00
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
      state         = ["running"]
      "instance-id" = [aws_instance.ecs.id]
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
