locals {
  module_path    = "eks/pod_identity"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../../../eks/cluster"
}

dependency "sms_secret" {
  config_path = "../../secrets/sms_provider"
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
  service_account_name = "shop-notifier"
  role_name            = "eks-prod-shop-notifier"
  policy_name          = "eks-prod-shop-notifier-policy"
  policy_description   = "SMS provider credential read for shop_notifier"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSmsProviderSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [dependency.sms_secret.outputs.secret_arn]
      },
    ]
  })
}
