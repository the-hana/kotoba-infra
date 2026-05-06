# DEVLOG — kotoba-infra

## 2026-05-06

### Terraform Remote State 用 bootstrap リソースを作成

- `bootstrap/` ディレクトリに S3 バケット + DynamoDB テーブルの Terraform コードを追加
- S3: バージョニング有効・AES256 暗号化・パブリックアクセス完全ブロック
- DynamoDB: PAY_PER_REQUEST（Free Tier 範囲内）、LockID でState競合を防止
- bootstrap はメインの Remote State 設定より先に1回だけ実行する必要があるため、
  独立ディレクトリに分離。メインの `backend.tf` と循環依存が発生しないようにする設計。
