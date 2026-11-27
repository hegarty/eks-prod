locals {
  module_path    = "eks/addons/aws"
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

# Without this, every aws_eks_pod_identity_association (karpenter's included)
# is inert - the association just records intent; this DaemonSet is what
# actually injects credentials into the pod at admission time. Needs no IAM
# role of its own - it's a local credential-vending proxy, not an AWS API
# caller.
inputs = {
  cluster_name                = dependency.cluster.outputs.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = "v1.4.1-eksbuild.3"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = {}
}
