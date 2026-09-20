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
  service_account_name = "shop-analytics"
  role_name            = "eks-prod-shop-analytics"
  policy_name          = "eks-prod-shop-analytics-policy"
  policy_description   = "DB secret read + raw archive read (reprocessing) for shop_analytics"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [dependency.rds.outputs.secret_arn]
      },
      {
        Sid    = "ReadRawArchive"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          dependency.raw_archive.outputs.bucket_arn,
          "${dependency.raw_archive.outputs.bucket_arn}/*",
        ]
      },
    ]
  })
}
