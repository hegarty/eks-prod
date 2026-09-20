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

# Single NAT gateway exists in only one AZ. Point every controller-subnet AZ's
# route table at that same NAT (the standard single-NAT-multi-AZ pattern) —
# the underlying `routes` module matches nat_ids by AZ key, so without this
# remap only the NAT's own AZ would get a working default route. (Computed
# inline in `inputs`, not `locals` — see ../../nat/terragrunt.hcl comment.)
inputs = {
  route-table_prefix = "eks-prod_controller"
  vpc_id             = dependency.vpc.outputs.vpc_id
  subnets            = dependency.vpc.outputs.controller_subnets
  destination_cidr   = "0.0.0.0/0"
  nat_ids            = { for az in keys(dependency.vpc.outputs.controller_subnets) : az => values(dependency.nat.outputs.ids)[0] }
}
