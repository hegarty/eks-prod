locals {
  module_path    = "rds-postgres"
  module_version = "v1.0.0"
}

dependency "vpc" {
  config_path = "../../../networking/vpc"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  identifier = "commerce-intel"
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = values(dependency.vpc.outputs.worker_subnets)
  db_name    = "commerce_intel"

  # No dedicated app/node security group exists in this cluster (nodes use
  # the VPC default SG — see eks/node_group), so ingress is CIDR-scoped to
  # the VPC rather than SG-referenced.
  allowed_cidr_blocks = [dependency.vpc.outputs.vpc_cidr]

  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  max_allocated_storage   = 100
  multi_az                = false # MVP: single-AZ, see ADR-006
  backup_retention_period = 7
  deletion_protection     = true
  skip_final_snapshot     = false

  tags = {
    Environment = "prod"
    Project     = "commerce-intel"
  }
}
