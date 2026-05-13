terraform {
  backend "s3" {
    # bootstrap apply 後、実際のバケット名に置換してから terraform init を実行すること
    # 例: kotoba-ai-tfstate-XXXXXX の XXXXXX は AWS アカウント ID 下 6 桁
    bucket         = "kotoba-ai-tfstate-XXXXXX"
    key            = "kotoba-ai/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "kotoba-ai-tfstate-lock"
    encrypt        = true
  }
}
