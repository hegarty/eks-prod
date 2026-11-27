locals {
  module_path    = "eks/pod_identity"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../../cluster"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name          = dependency.cluster.outputs.cluster_name
  namespace             = "kube-system"
  service_account_name  = "ebs-csi-controller-sa"
  role_name             = "eks-prod-ebs-csi-driver"
  aws_managed_policies  = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
}
