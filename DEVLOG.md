# DEVLOG — kotoba-infra

## 2026-06-13

### 再デプロイ自動化スクリプト追加

- `scripts/setup.sh` を追加
- `terraform apply` 後に実行すると、`terraform output` から値を取得して GitHub Secrets (kotoba-api / kotoba-web) を自動更新
- 対象 Secrets: `AWS_ROLE_ARN`, `S3_BUCKET`, `CF_DISTRIBUTION_ID`, `VITE_API_BASE_URL`
- スクリプト上部にアカウント解約後の再デプロイ手順 (8ステップ) をコメントで記載
- 背景: 無料プランでは6ヶ月後にアカウント解約される。再デプロイ時に4つの GitHub Secrets を手動更新する手間を省くため。

## 2026-05-27

### CD パイプライン実装 (PR 6)

- `outputs.tf`: ECR / ECS / IAM outputs 追加 (3 → 7個)
  - `ecr_repository_url`: GitHub Actions の docker push 先
  - `ecs_cluster_name` / `ecs_service_name`: ECS サービス更新用
  - `github_actions_role_arn`: GitHub Secrets `AWS_ROLE_ARN` の設定値
- `kotoba-api/.github/workflows/deploy.yml`: ECR build/push → ECS Task Definition 更新 → ECS deploy
  - `workflow_run` トリガー: CI 成功後のみ実行 (CI 失敗時は deploy をスキップ)
  - `:sha` と `:latest` の2タグを同時 push、`:latest` を次回ビルドの Docker layer cache として活用
  - `wait-for-service-stability: false`: t2.micro 1台構成で安定化待機が意味をなさないため
  - OIDC 認証 (Secrets 1個: `AWS_ROLE_ARN`)
- `kotoba-web/.github/workflows/deploy.yml`: pnpm build → S3 sync (2段階) → CloudFront invalidation
  - `VITE_API_BASE_URL` を Secrets から注入 (未設定だとビルド後の API 接続が全て失敗するため)
  - 静的アセット (JS/CSS/画像): `immutable` キャッシュ (Vite が hash 付きファイル名を生成)
  - `index.html` / JSON: `no-cache` (常に最新バージョンを取得)
  - OIDC 認証 (Secrets 4個: `AWS_ROLE_ARN`, `S3_BUCKET`, `CF_DISTRIBUTION_ID`, `VITE_API_BASE_URL`)

## 2026-05-24

### AI パイプライン実装 (PR 5)

- `lambda/` ディレクトリ + Python 3.12 Lambda × 5
- `sqs.tf`: daily_story キュー + DLQ (MaxReceiveCount=3)
- `lambda.tf`: Lambda × 5 + archive_file + CloudWatch Log Group × 5
- `eventbridge.tf`: EventBridge Rule × 5 (スケジュール + イベントパターン)
- `cloudwatch.tf`: DLQ アラーム + SNS メール通知
- `iam.tf`: Lambda policy の Resource を実 ARN に絞り込み (TODO 解決)

**Lambda 設計方針**
- `daily_story`: SQS トリガー → Rails webhook POST。Gemini 呼び出しと DB 保存は Rails 側に委譲。Lambda をステートレスに保ち、ビジネスロジックを API サーバーに集約。
- `rds_stop`: RDS-EVENT-0088 (AWS が 7 日後に自動起動) を捕捉して即停止。Free Tier の RDS 自動起動問題への対処。
- `ec2_stop` / `ec2_start`: ECS desired_count を 0 ↔ 1 で切り替え (EC2 は停止しない)。深夜 (JST 03:00) に停止、朝 (JST 09:00) に再開。
- `cf_origin_updater`: EC2 running イベントの payload から instance-id を取得し、新しいパブリック IP を CloudFront origin に直接書き込む。SSM から distribution ID を取得することで Terraform state に依存しない実装。

**IAM 最小権限化**
- Lambda の ECS / RDS / CloudFront 権限の Resource を `"*"` から実 ARN に変更。PR 2 の TODO コメントを全て解決。

## 2026-05-18

### S3 + CloudFront フロントエンド配信を追加 (PR 4)

- `s3_frontend.tf`: kotoba-web 静的ホスティング用 S3 バケット + OAC + バケットポリシー
- `cloudfront.tf`: CloudFront Distribution (S3 + EC2 の 2 Origin 構成) + SSM cf_distribution_id
- `outputs.tf`: cloudfront_domain_name / cloudfront_distribution_id / s3_frontend_bucket

**CloudFront 設計**
- Default Behavior `/*` → S3 (React SPA)。`/api/*` と `/webhooks/*` → EC2:3000 (HTTP) に分岐。
- CloudFront が HTTPS プロキシとなり EC2 の HTTP を隠蔽。Mixed Content 問題を解消。
- SPA の React Router 対応: S3 が返す 403/404 をすべて `index.html` にリダイレクト (custom_error_response)。
- PriceClass_200 (アジア + US + EU)。CloudFront ログは S3 ストレージコスト増につき無効化。

**OAC 採用理由**
- 旧来の OAI (Origin Access Identity) より権限制御が精細で、AWS 推奨の新方式。
- S3 バケットポリシーに `aws:SourceArn` 条件を付与し、自 Distribution のみアクセス可能にした。

**EC2 origin の IP 管理**
- EC2 は Elastic IP 未使用のため再起動で IP が変わる。Terraform apply 時は `aws_instance.ecs.public_ip` で初期値を設定。
- 以降の IP 変更は PR 5 で実装する Lambda (cf_origin_updater) が自動更新する。
- Lambda が参照できるよう Distribution ID を SSM `/kotoba-ai/cf_distribution_id` に保存。

## 2026-05-13

### Compute + DB リソース追加 (PR 3)

- `rds.tf`: DB Subnet Group + RDS db.t3.micro (PostgreSQL 16, 20GB) + DATABASE_URL を SSM に保存
  - `publicly_accessible=false` でセキュリティと費用を同時に最適化（NAT Gateway 不要）
  - `backup_retention_period=0` で Free Tier の 20GB バックアップ上限を超えないよう設定
  - `urlencode()` で DATABASE_URL のパスワード特殊文字をエスケープ
- `ecs.tf`: EC2 Instance Role + ECS Cluster + Task Definition + EC2 t2.micro + ECS Service
  - ECS ホスト EC2 に swap 1.5GB を `fallocate` で作成し `/etc/fstab` で永続化（t2.micro OOM 防止）
  - `deployment_minimum_healthy_percent=0`: t2.micro 1 台での rolling update を可能にするトレードオフ
  - `RAILS_LOG_TO_STDOUT=true` を Task Definition に設定し CloudWatch Logs へ直接転送
  - Elastic IP 不使用（中止時 IP 自動解放、費用ゼロ）
- `variables.tf`: `db_name` / `db_username` 変数を追加（デフォルト値あり）

### メイン Terraform 基盤ファイル群を追加 (PR 2)

- `versions.tf` / `backend.tf` / `variables.tf` / `locals.tf` / `networking.tf` / `ecr.tf` / `iam.tf` / `ssm.tf` / `terraform.tfvars.example` を新規作成

**ネットワーク設計**
- VPC 10.0.0.0/16 + Public Subnet ×2 (1a / 1c)。NAT Gateway を意図的に排除し Public Subnet + SG のみで接続制御。月額 $45 のコスト削減が主目的。
- RDS DB Subnet Group が最低 2AZ を要求するため、実際に配置するのは 1a のみでもサブネットは 2 つ用意。
- SG: kotoba-ecs は 3000/tcp のみ open（CloudFront origin）。kotoba-rds は kotoba-ecs SG からの 5432/tcp のみ許可。SG 名変更時の apply 失敗を防ぐため `lifecycle { create_before_destroy = true }` を両 SG に付与。

**IAM 設計**
- `data "aws_caller_identity"` で account_id を取得し、SSM ARN のワイルドカード (`*`) を排除。同一アカウント内でも明示的に account_id を指定するのが最小権限原則の観点で正しい。
- GitHub OIDC の信頼条件を `repo:org/*` ではなく `kotoba-api` / `kotoba-web` の 2 リポジトリに限定。org 全体に AssumeRole を許可するのはセキュリティリスク。
- ECR 権限を `GetAuthorizationToken`（Resource=`*` 必須, AWS 仕様）と push 系アクション（Resource=ECR ARN）に分離。まとめると push 権限が全 ECR リポジトリに広がるため分割が必要。
- Lambda の ECS / RDS / CloudFront `Resource = "*"` はリソース ARN が PR 3〜4 で確定するため暫定。PR 5 (Lambda 実装) で絞り込む旨を TODO コメントで明示。

**SSM**
- `jwt_secret` / `gemini_api_key` を SecureString で保存。DB URL は RDS endpoint 依存のため PR 3、CloudFront distribution ID は PR 4 で追加予定。

## 2026-05-06

### bootstrap 追加レビュー指摘を修正

- `aws_s3_bucket_lifecycle_configuration` に `filter {}` を追加（省略すると perpetual diff が発生するため明示）
- 同リソースに `depends_on = [aws_s3_bucket_versioning.tfstate]` を追加（バージョニング有効化前にlifecycle ruleが適用されるレースコンディションを防止）
- `lifecycle { prevent_destroy }` ブロックをリソース末尾へ移動（Terraform コミュニティ慣例）

### bootstrap のコードレビュー指摘を修正

- `.gitignore` に Terraform 標準除外項目を追加（`.terraform/`, `*.tfstate`, `*.tfvars` 等）
  - `.terraform.lock.hcl` はコミット対象のため除外しない（Provider バージョン再現性の担保）
- `aws_s3_bucket` と `aws_dynamodb_table` に `lifecycle { prevent_destroy = true }` を追加
  - State が消えると全リソースが管理不能になるため、誤 destroy を防止する
- `required_version` を `>= 1.7` から `~> 1.7` に変更（Terraform 2.x を誤って許容しないよう範囲を限定）
- `tfstate_bucket_name` の default 値を削除 — S3 バケット名はグローバル一意のため、実行者が明示的に指定する設計に変更
- `terraform.tfvars.example` を追加（バケット名命名規則のガイドとして）
- S3 lifecycle rule を追加（旧バージョンを 90 日で自動削除。Free Tier の容量節約）
- bootstrap README に ⚠️ ローカル State の保管方法を追記

### Terraform Remote State 用 bootstrap リソースを作成

- `bootstrap/` ディレクトリに S3 バケット + DynamoDB テーブルの Terraform コードを追加
- S3: バージョニング有効・AES256 暗号化・パブリックアクセス完全ブロック
- DynamoDB: PAY_PER_REQUEST（Free Tier 範囲内）、LockID でState競合を防止
- bootstrap はメインの Remote State 設定より先に1回だけ実行する必要があるため、
  独立ディレクトリに分離。メインの `backend.tf` と循環依存が発生しないようにする設計。
