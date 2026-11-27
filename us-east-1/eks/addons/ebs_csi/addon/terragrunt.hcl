locals {
  module_path    = "eks/addons/aws"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../../cluster"
}

dependency "role" {
  config_path = "../role"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Without this, every StorageClass referencing `provisioner: ebs.csi.aws.com`
# (gp3, see ../../../storage_class) can never actually provision a volume -
# PVCs sit in ExternalProvisioning forever and anything depending on one
# (kube-prometheus-stack's Prometheus/Grafana, loki, redpanda, tempo) times
# out on its Helm wait regardless of node capacity.
inputs = {
  cluster_name                = dependency.cluster.outputs.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.68.1-eksbuild.1"
  service_role_arn            = dependency.role.outputs.role_arn
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = {}
}
