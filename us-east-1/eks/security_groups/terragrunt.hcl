locals {
  ingress        = file("ingress.json")
  egress         = file("egress.json")
  module_path    = "networking/security_groups"
  module_version = "v1.0.0"
}

dependency "vpc" {
  config_path = "../../networking/vpc"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  sg_prefix     = "eks-prod"
  vpc_id        = dependency.vpc.outputs.vpc_id
  ingress_rules = local.ingress
  egress_rules  = local.egress

  # Discoverable by Karpenter's EC2NodeClass securityGroupSelectorTerms —
  # see eks/manifests/karpenter/ec2nodeclass.yaml.
  tags = {
    "karpenter.sh/discovery" = "eks-prod"
  }
}
