# ──────────────────────────────────────────
# ECS 最適化 AMI (Amazon Linux 2023)
# AWS SSM Parameter Store からリージョン別最新 AMI ID を取得
# ──────────────────────────────────────────
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# ──────────────────────────────────────────
# EC2 Instance Role
# EC2 → ECS クラスター登録 + CloudWatch Logs 書き込みに必要
# ──────────────────────────────────────────
resource "aws_iam_role" "ecs_instance" {
  name = "kotoba-ecs-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "kotoba-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

# ──────────────────────────────────────────
# ECS Cluster
# 名前は user_data の ECS_CLUSTER 設定と一致させること
# ──────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "kotoba-api"

  tags = local.common_tags
}

# ──────────────────────────────────────────
# CloudWatch Log Group
# retention_in_days=7: Free Tier 5GB 超過防止
# ──────────────────────────────────────────
resource "aws_cloudwatch_log_group" "ecs_api" {
  name              = "/ecs/kotoba-api"
  retention_in_days = 7

  tags = local.common_tags
}

# ──────────────────────────────────────────
# ECS Task Definition
# bridge ネットワーク / CPU 256 / Memory hard 768 soft 512
# SSM secrets injection: DATABASE_URL, JWT_SECRET_KEY, GEMINI_API_KEY
# RAILS_LOG_TO_STDOUT=true で CloudWatch Logs に転送
# ──────────────────────────────────────────
resource "aws_ecs_task_definition" "api" {
  family                   = "kotoba-api"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "kotoba-api"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true
      cpu       = 256
      memory    = 768
      memoryReservation = 512

      portMappings = [{
        containerPort = 3000
        hostPort      = 3000
        protocol      = "tcp"
      }]

      environment = [
        { name = "RAILS_ENV",           value = "production" },
        { name = "PORT",                value = "3000" },
        { name = "RAILS_LOG_TO_STDOUT", value = "true" }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_ssm_parameter.database_url.arn
        },
        {
          name      = "JWT_SECRET_KEY"
          valueFrom = aws_ssm_parameter.jwt_secret.arn
        },
        {
          name      = "GEMINI_API_KEY"
          valueFrom = aws_ssm_parameter.gemini_api_key.arn
        },
        {
          name      = "RAILS_MASTER_KEY"
          valueFrom = aws_ssm_parameter.rails_master_key.arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ──────────────────────────────────────────
# EC2 Instance (ECS ホスト)
# t3.micro Free Tier / public_a サブネット
# Elastic IP 不使用: 停止時 IP 自動解放で費用ゼロ
# user_data: ECS_CLUSTER 登録 + swap 1.5GB + fstab 永続化
# ──────────────────────────────────────────
resource "aws_instance" "ecs" {
  ami                    = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.ecs.id]
  iam_instance_profile   = aws_iam_instance_profile.ecs.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  # ami: ECS最適化AMIは定期更新されるため ignore — 意図しない再作成を防ぐ
  # root_block_device: spec変更による意図しない再作成を防ぐ
  lifecycle {
    ignore_changes = [ami, root_block_device]
  }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -e

    # ECS クラスター登録
    echo "ECS_CLUSTER=kotoba-api" >> /etc/ecs/ecs.config
    echo 'ECS_AVAILABLE_LOGGING_DRIVERS=["json-file","awslogs"]' >> /etc/ecs/ecs.config

    # swap 1.5GB 作成 (t3.micro OOM 防止)
    if [ ! -f /swapfile ]; then
      fallocate -l 1536M /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
  EOT
  )

  tags = merge(local.common_tags, { Name = "kotoba-ecs-host" })
}

# ──────────────────────────────────────────
# ECS Service
# minimum_healthy_percent=0: t3.micro 1台での rolling update を可能にする
# ──────────────────────────────────────────
resource "aws_ecs_service" "api" {
  name            = "kotoba-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = 1
  launch_type     = "EC2"

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # EC2 がクラスターに登録される前に service がタスク配置を試みるのを防ぐ
  depends_on = [aws_instance.ecs]

  # CD パイプラインが task_definition を更新した後に Terraform が旧 revision に戻すのを防ぐ
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }

  tags = local.common_tags
}
