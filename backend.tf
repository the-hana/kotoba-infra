terraform {
  backend "s3" {
    # bootstrap apply 後、実際のバケット名に置換してから terraform init を実行すること
    # 例: kotoba-tfstate-043189681175 (AWS アカウント ID 全 12 桁をそのまま末尾に付与)
    bucket         = "kotoba-tfstate-043189681175"
    key            = "kotoba-ai/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "kotoba-ai-tfstate-lock"
    encrypt        = true
  }
}
