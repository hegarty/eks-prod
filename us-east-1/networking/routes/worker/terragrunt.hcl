locals {
  module_path    = "networking/routes"
  module_version = "v1.0.0"
}

dependency "vpc" {
  config_path = "../../vpc"
}

dependency "nat" {
  config_path = "../../nat"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Same single-NAT remap as ../controller — see the comment there.
inputs = {
  route-table_prefix = "eks-prod_worker"
  vpc_id             = dependency.vpc.outputs.vpc_id
  subnets            = dependency.vpc.outputs.worker_subnets
  destination_cidr   = "0.0.0.0/0"
  nat_ids            = { for az in keys(dependency.vpc.outputs.worker_subnets) : az => values(dependency.nat.outputs.ids)[0] }
}
