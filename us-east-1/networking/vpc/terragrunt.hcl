locals {
  vpc_name       = "shared"
  module_path    = "networking/vpc"
  module_version = "v1.0.0"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  vpc_name             = local.vpc_name
  vpc_cidr             = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Only 2 AZs (EKS's minimum for the control plane) — cost-conscious MVP,
  # not the 3-AZ spread eks-dev uses. See docs/cost-model.md.
  subnets = [
    {
      availability_zone_id = "use1-az1"
      cidr                 = "10.1.0.0/24"
      tags = {
        "kubernetes.io/cluster/eks-prod"  = "shared"
        "kubernetes.io/role/internal-elb" = "1"
        "use"                             = "controller"
        "type"                            = "private"
      }
    },
    {
      availability_zone_id = "use1-az2"
      cidr                 = "10.1.1.0/24"
      tags = {
        "kubernetes.io/cluster/eks-prod"  = "shared"
        "kubernetes.io/role/internal-elb" = "1"
        "use"                             = "controller"
        "type"                            = "private"
      }
    },
    {
      availability_zone_id = "use1-az1"
      cidr                 = "10.1.20.0/25"
      tags = {
        "kubernetes.io/cluster/eks-prod" = "shared"
        "kubernetes.io/role/elb"         = "1"
        "use"                            = "ingress-egress"
        "type"                           = "public"
      }
    },
    {
      availability_zone_id = "use1-az2"
      cidr                 = "10.1.20.128/25"
      tags = {
        "kubernetes.io/cluster/eks-prod" = "shared"
        "kubernetes.io/role/elb"         = "1"
        "use"                            = "ingress-egress"
        "type"                           = "public"
      }
    },
    {
      availability_zone_id = "use1-az1"
      cidr                 = "10.1.8.0/22"
      tags = {
        "kubernetes.io/cluster/eks-prod"  = "shared"
        "kubernetes.io/role/internal-elb" = "1"
        "use"                             = "worker"
        "type"                            = "private"
        "karpenter.sh/discovery"          = "eks-prod"
      }
    },
    {
      availability_zone_id = "use1-az2"
      cidr                 = "10.1.12.0/22"
      tags = {
        "kubernetes.io/cluster/eks-prod"  = "shared"
        "kubernetes.io/role/internal-elb" = "1"
        "use"                             = "worker"
        "type"                            = "private"
        "karpenter.sh/discovery"          = "eks-prod"
      }
    },
  ]
}
