# ──────────────────────────────────────────
# Lambda zip パッケージ (archive_file)
# terraform plan/apply 時にローカルで zip 生成
# 生成物 (*.zip) は .gitignore で除外
# ──────────────────────────────────────────
data "archive_file" "daily_story" {
  type        = "zip"
  source_file = "${path.module}/lambda/daily_story.py"
  output_path = "${path.module}/lambda/daily_story.zip"
}

data "archive_file" "rds_stop" {
  type        = "zip"
  source_file = "${path.module}/lambda/rds_stop.py"
  output_path = "${path.module}/lambda/rds_stop.zip"
}

data "archive_file" "ec2_stop" {
  type        = "zip"
  source_file = "${path.module}/lambda/ec2_stop.py"
  output_path = "${path.module}/lambda/ec2_stop.zip"
}

data "archive_file" "ec2_start" {
  type        = "zip"
  source_file = "${path.module}/lambda/ec2_start.py"
  output_path = "${path.module}/lambda/ec2_start.zip"
}

data "archive_file" "cf_origin_updater" {
  type        = "zip"
  source_file = "${path.module}/lambda/cf_origin_updater.py"
  output_path = "${path.module}/lambda/cf_origin_updater.zip"
}

# ──────────────────────────────────────────
# CloudWatch Log Groups (retention=7日)
# ──────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_daily_story" {
  name              = "/aws/lambda/kotoba-daily-story"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_rds_stop" {
  name              = "/aws/lambda/kotoba-rds-stop"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_ec2_stop" {
  name              = "/aws/lambda/kotoba-ec2-stop"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_ec2_start" {
  name              = "/aws/lambda/kotoba-ec2-start"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "lambda_cf_origin_updater" {
  name              = "/aws/lambda/kotoba-cf-origin-updater"
  retention_in_days = 7
  tags              = local.common_tags
}

# ──────────────────────────────────────────
# Lambda: daily_story
# SQS トリガー → Rails webhook POST → スト生成
# ──────────────────────────────────────────
resource "aws_lambda_function" "daily_story" {
  function_name = "kotoba-daily-story"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "daily_story.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.daily_story.output_path
  source_code_hash = data.archive_file.daily_story.output_base64sha256

  environment {
    variables = {
      WEBHOOK_URL = "https://${aws_cloudfront_distribution.main.domain_name}/webhooks/daily_story"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_daily_story]

  tags = local.common_tags
}

# SQS → Lambda イベントソースマッピング
resource "aws_lambda_event_source_mapping" "daily_story" {
  event_source_arn = aws_sqs_queue.daily_story.arn
  function_name    = aws_lambda_function.daily_story.arn
  batch_size       = 1
}

# ──────────────────────────────────────────
# Lambda: rds_stop
# RDS 自動再起動イベント → RDS 再停止
# ──────────────────────────────────────────
resource "aws_lambda_function" "rds_stop" {
  function_name = "kotoba-rds-stop"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "rds_stop.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.rds_stop.output_path
  source_code_hash = data.archive_file.rds_stop.output_base64sha256

  environment {
    variables = {
      RDS_INSTANCE_ID = aws_db_instance.main.identifier
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_rds_stop]

  tags = local.common_tags
}

# ──────────────────────────────────────────
# Lambda: ec2_stop
# JST 03:00 → ECS desired_count=0
# ──────────────────────────────────────────
resource "aws_lambda_function" "ec2_stop" {
  function_name = "kotoba-ec2-stop"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "ec2_stop.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.ec2_stop.output_path
  source_code_hash = data.archive_file.ec2_stop.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.main.name
      ECS_SERVICE = aws_ecs_service.api.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_ec2_stop]

  tags = local.common_tags
}

# ──────────────────────────────────────────
# Lambda: ec2_start
# JST 09:00 → ECS desired_count=1
# ──────────────────────────────────────────
resource "aws_lambda_function" "ec2_start" {
  function_name = "kotoba-ec2-start"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "ec2_start.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.ec2_start.output_path
  source_code_hash = data.archive_file.ec2_start.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.main.name
      ECS_SERVICE = aws_ecs_service.api.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_ec2_start]

  tags = local.common_tags
}

# ──────────────────────────────────────────
# Lambda: cf_origin_updater
# EC2 running イベント → CloudFront origin IP 更新
# ──────────────────────────────────────────
resource "aws_lambda_function" "cf_origin_updater" {
  function_name = "kotoba-cf-origin-updater"
  role          = aws_iam_role.lambda.arn
  runtime       = "python3.12"
  handler       = "cf_origin_updater.handler"
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.cf_origin_updater.output_path
  source_code_hash = data.archive_file.cf_origin_updater.output_base64sha256

  environment {
    variables = {
      CF_DIST_ID_PARAM = aws_ssm_parameter.cf_distribution_id.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_cf_origin_updater]

  tags = local.common_tags
}
