locals {
  module_path    = "eks/addons/helm"
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

# Karpenter ships its CRDs as a separate chart from the controller — the
# main `karpenter` chart does not bundle them. This must apply before
# ../karpenter (the controller) and before manifests/karpenter/*.yaml
# (NodePool/EC2NodeClass), both of which need these CRDs to already exist.
inputs = {
  cluster_name  = dependency.cluster.outputs.cluster_name
  release_name  = "karpenter-crd"
  repository    = "oci://public.ecr.aws/karpenter"
  chart         = "karpenter-crd"
  chart_version = "1.6.1"
  namespace     = "kube-system"
  helm_values   = {}
}
