locals {
  module_path    = "eks/access_entries/users"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../cluster"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name = dependency.cluster.outputs.cluster_name

  principal_arn     = "arn:aws:iam::868150784168:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_org-admin_2dd1059a3aefa8c4"
  policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope_type = "cluster"
}
