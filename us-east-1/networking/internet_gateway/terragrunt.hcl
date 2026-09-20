locals {
  module_path    = "networking/internet_gateway"
  module_version = "v1.0.0"
}

dependency "vpc" {
  config_path = "../vpc"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  name   = "eks-prod_internet-gateway"
  vpc_id = dependency.vpc.outputs.vpc_id
}
