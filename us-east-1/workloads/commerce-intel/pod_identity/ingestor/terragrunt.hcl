locals {
  module_path    = "eks/pod_identity"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../../../eks/cluster"
}

dependency "raw_archive" {
  config_path = "../../s3/raw_archive"
}

dependency "shopify_secret" {
  config_path = "../../secrets/shopify_devmoto"
}

dependency "rds" {
  config_path = "../../rds"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name         = dependency.cluster.outputs.cluster_name
  namespace            = "commerce-intel"
  service_account_name = "shop-ingestor"
  role_name            = "eks-prod-shop-ingestor"
  policy_name          = "eks-prod-shop-ingestor-policy"
  policy_description   = "Raw event archive write + Shopify/DB secret read for shop_ingestor"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteRawArchive"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${dependency.raw_archive.outputs.bucket_arn}/*"]
      },
      {
        Sid    = "ReadIngestSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          dependency.shopify_secret.outputs.secret_arn,
          dependency.rds.outputs.secret_arn,
        ]
      },
    ]
  })
}
