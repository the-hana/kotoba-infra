# DEVLOG — kotoba-infra

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

## 2026-05-06

### Terraform Remote State 用 bootstrap リソースを作成

- `bootstrap/` ディレクトリに S3 バケット + DynamoDB テーブルの Terraform コードを追加
- S3: バージョニング有効・AES256 暗号化・パブリックアクセス完全ブロック
- DynamoDB: PAY_PER_REQUEST（Free Tier 範囲内）、LockID でState競合を防止
- bootstrap はメインの Remote State 設定より先に1回だけ実行する必要があるため、
  独立ディレクトリに分離。メインの `backend.tf` と循環依存が発生しないようにする設計。
