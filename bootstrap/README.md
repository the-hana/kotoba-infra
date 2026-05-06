# bootstrap

Terraform Remote State 用リソースを作成する1回限りのセットアップ。

## 作成されるリソース

| リソース | 名前 |
|---|---|
| S3 バケット | `kotoba-ai-tfstate` |
| DynamoDB テーブル | `kotoba-ai-tfstate-lock` |

## 実行方法

```bash
cd bootstrap
terraform init
terraform apply
```

メインの Terraform を初めて実行する前に1回だけ実行する。
その後は `cd ..` してメインの `terraform init` を実行する。
