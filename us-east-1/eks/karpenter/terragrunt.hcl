locals {
  module_path    = "eks/karpenter"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../cluster"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name            = dependency.cluster.outputs.cluster_name
  cluster_arn             = dependency.cluster.outputs.cluster_id.arn
  namespace               = "kube-system"
  service_account_name    = "karpenter"
  controller_role_name    = "eks-prod-karpenter-controller"
  node_role_name          = "eks-prod-karpenter-node"
  interruption_queue_name = "eks-prod-karpenter-interruption"
}
