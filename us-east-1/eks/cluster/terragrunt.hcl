locals {
  module_path    = "eks/cluster"
  module_version = "v1.0.0"
}

dependency "iam" {
  config_path = "../iam/cluster_role"
}

dependency "vpc" {
  config_path = "../../networking/vpc"
}

dependency "sg" {
  config_path = "../security_groups"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name = "eks-prod"

  # Pure API auth mode — no aws-auth ConfigMap. Modern EKS default; access is
  # granted exclusively through the access_entries/* units.
  authentication_mode                         = "API"
  bootstrap_cluster_creator_admin_permissions = false

  iam_arn         = dependency.iam.outputs.arn
  vpc_id          = dependency.vpc.outputs.vpc_id
  subnet_ids      = dependency.vpc.outputs.controller_subnets
  security_groups = [dependency.sg.outputs.id]

  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = ["0.0.0.0/0"]

  # Cheaper default from the eks/cluster module — skips authenticator/
  # controllerManager/scheduler logs. Bump back to the full 5-type list if
  # you need to debug the control plane itself.
  enabled_cluster_log_types = ["api", "audit"]
}
