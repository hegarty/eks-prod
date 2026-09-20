locals {
  module_path    = "networking/routes"
  module_version = "v1.0.0"
}

dependency "vpc" {
  config_path = "../../vpc"
}

dependency "gateway" {
  config_path = "../../internet_gateway"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  route-table_prefix = "eks-prod_public"
  vpc_id             = dependency.vpc.outputs.vpc_id
  subnets            = dependency.vpc.outputs.public_subnets
  destination_cidr   = "0.0.0.0/0"
  gateway_id         = dependency.gateway.outputs.id
}
