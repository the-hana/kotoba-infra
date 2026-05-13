locals {
  project = "kotoba-ai"
  env     = "prod"

  common_tags = {
    project = local.project
    env     = local.env
  }

  az_a = "${var.aws_region}a"
  az_c = "${var.aws_region}c"
}
