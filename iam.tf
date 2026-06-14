data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────
# ECS Task Execution Role
# ECR イメージ pull + CloudWatch Logs + SSM secrets injection
# ──────────────────────────────────────────
resource "aws_iam_role" "ecs_execution" {
  name = "kotoba-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "ssm-read"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameters", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kotoba-ai/*"
    }]
  })
}

# ──────────────────────────────────────────
# ECS Task Role (アプリ実行時ロール)
# Rails アプリ自体に必要な AWS 権限 — 現時点では最小権限
# ──────────────────────────────────────────
resource "aws_iam_role" "ecs_task" {
  name = "kotoba-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

# ──────────────────────────────────────────
# Lambda Execution Role
# daily_story / rds_stop / ec2_stop / ec2_start / cf_origin_updater 共通
# ──────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "kotoba-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_services" {
  name = "services"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # SQS: daily_story キューからメッセージ受信
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = [aws_sqs_queue.daily_story.arn]
      },
      {
        # ECS: ec2_stop / ec2_start Lambda が desired_count を更新
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
        Resource = [aws_ecs_service.api.id]
      },
      {
        # RDS: rds_stop Lambda が DB インスタンスを停止、ec2_start Lambda が起動
        Effect   = "Allow"
        Action   = ["rds:StopDBInstance", "rds:StartDBInstance", "rds:DescribeDBInstances"]
        Resource = [aws_db_instance.main.arn]
      },
      {
        # EC2: ec2_stop / ec2_start Lambda が EC2 インスタンスを起動・停止
        Effect   = "Allow"
        Action   = ["ec2:StopInstances", "ec2:StartInstances"]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.ecs.id}"
      },
      {
        # CloudFront: cf_origin_updater Lambda が origin を更新
        Effect   = "Allow"
        Action   = ["cloudfront:GetDistributionConfig", "cloudfront:UpdateDistribution"]
        Resource = [aws_cloudfront_distribution.main.arn]
      },
      {
        # EC2: cf_origin_updater Lambda が新しいパブリック IP を取得
        # DescribeInstances/DescribeNetworkInterfaces はリソースレベル制限不可 (AWS 仕様)
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces"]
        Resource = "*"
      },
      {
        # SSM: daily_story Lambda が Webhook URL などを取得
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/kotoba-ai/*"
      }
    ]
  })
}

# ──────────────────────────────────────────
# GitHub Actions OIDC
# kotoba-api (ECR push + ECS deploy) と kotoba-web (S3 sync + CF invalidation)
# ──────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  tags = local.common_tags
}

resource "aws_iam_role" "github_actions" {
  name = "kotoba-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${var.github_org}/kotoba-api:*",
            "repo:${var.github_org}/kotoba-web:*"
          ]
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECR: 認証トークン取得 — AWS 仕様上 Resource = "*" が必須
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # ECR: イメージプッシュ — kotoba-api リポジトリのみに限定
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = aws_ecr_repository.api.arn
      },
      {
        # ECS: サービス更新・タスク定義登録
        Effect   = "Allow"
        Action   = ["ecs:UpdateService", "ecs:DescribeServices", "ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition"]
        Resource = "*"
      },
      {
        # IAM PassRole: ECS タスク定義登録時に必要
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_execution.arn, aws_iam_role.ecs_task.arn]
      },
      {
        # S3: kotoba-web 静的ファイルのデプロイ
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = ["arn:aws:s3:::kotoba-web-*", "arn:aws:s3:::kotoba-web-*/*"]
      },
      {
        # CloudFront: キャッシュ無効化
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      }
    ]
  })
}
