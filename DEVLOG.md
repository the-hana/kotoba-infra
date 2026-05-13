# DEVLOG — kotoba-infra

## 2026-05-13

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
