locals {
  module_path    = "eks/access_entries/nodes"
  module_version = "v1.0.0"
}

dependency "karpenter" {
  config_path = "../../karpenter"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Karpenter-launched nodes assume a different IAM role than the static system
# node group, so they need their own access entry under pure API auth mode.
inputs = {
  cluster_name      = "eks-prod"
  principal_arn     = dependency.karpenter.outputs.node_role_arn
  node_type         = "EC2_LINUX"
  policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"
  access_scope_type = "cluster"
}
