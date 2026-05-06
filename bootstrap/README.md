# bootstrap

Terraform Remote State 用リソースを作成する1回限りのセットアップ。

## 作成されるリソース

| リソース | 名前 | 補足 |
|---|---|---|
| S3 バケット | `kotoba-ai-tfstate-<suffix>` | バージョニング・暗号化・パブリックアクセスブロック・lifecycle 90日 |
| DynamoDB テーブル | `kotoba-ai-tfstate-lock` | State Lock 用 |

## 実行方法

```bash
cd bootstrap

# 1. tfvars を作成（バケット名のサフィックスにAWSアカウントIDの下6桁を使う）
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars を編集して tfstate_bucket_name を設定

# 2. 実行
terraform init
terraform apply

# 3. メインの Terraform へ戻る
cd ..
terraform init
```

## ⚠️ bootstrap の terraform.tfstate について

bootstrap は Remote Backend を持たず、**State がローカルに保存される**。
このファイルを紛失すると S3/DynamoDB を Terraform で管理できなくなる。

- `bootstrap/terraform.tfstate` は `.gitignore` 対象（コミット禁止）
- 実行後は安全な場所にバックアップすること（例: 1Password のメモ, ローカル外部ドライブ）
- 紛失した場合は `terraform import` で復旧できるが手間がかかる
