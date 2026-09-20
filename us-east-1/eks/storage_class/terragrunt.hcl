locals {
  module_path    = "eks/storage_class"
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
  cluster_name     = dependency.cluster.outputs.cluster_name
  cluster_endpoint = dependency.cluster.outputs["api-server-endpoint"]
  cluster_ca       = dependency.cluster.outputs["certificate-authority"][0]["data"]
  region           = include.root.locals.aws_region
}
