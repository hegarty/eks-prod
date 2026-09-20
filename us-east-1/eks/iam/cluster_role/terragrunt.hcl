locals {
  module_path    = "iam"
  module_version = "v1.0.0"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  role_name          = "eks-prod_cluster-role"
  policy_name        = "eks-prod_cluster-policy"
  policy_description = "Cluster role used by the EKS control plane"

  # jsonencode()'d because the generic `iam` module's assume_role_policy
  # variable is typed as a plain string, not an object.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "eks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  aws_managed_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
  ]
}
