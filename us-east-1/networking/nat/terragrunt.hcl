locals {
  module_path    = "networking/nat_gateway"
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

# Single NAT Gateway — deliberate MVP cost tradeoff (~$33/mo instead of one
# per AZ). If that AZ has an outage, private-subnet egress breaks for both
# AZs until it recovers. See docs/disaster-recovery.md and docs/cost-model.md.
# (Terragrunt's `locals` block can't reference `dependency` outputs — that
# resolution only happens inside `inputs` — so this is computed inline here
# rather than as a local.)
inputs = {
  prefix = "eks-prod-nat"
  subnet_ids = {
    (keys(dependency.vpc.outputs.public_subnets)[0]) = dependency.vpc.outputs.public_subnets[keys(dependency.vpc.outputs.public_subnets)[0]]
  }
}
