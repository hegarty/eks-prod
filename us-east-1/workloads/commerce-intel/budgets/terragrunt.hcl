locals {
  module_path    = "budgets"
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
  budget_name         = "eks-prod-monthly"
  monthly_limit       = 250
  alert_thresholds    = [100, 150, 200, 250]
  notification_emails = ["me@terencehegarty.com"]

  tags = {
    Environment = "prod"
  }
}
