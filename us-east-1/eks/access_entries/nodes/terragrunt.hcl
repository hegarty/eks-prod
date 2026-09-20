locals {
  module_path    = "eks/access_entries/nodes"
  module_version = "v1.0.0"
}

dependency "node_role" {
  config_path = "../../iam/node_role"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name      = "eks-prod"
  principal_arn     = dependency.node_role.outputs.arn
  node_type         = "EC2_LINUX"
  policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"
  access_scope_type = "cluster"
}
