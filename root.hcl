# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION
# Terragrunt is a thin wrapper for Terraform/OpenTofu that provides extra tools for working with multiple modules,
# remote state, and locking: https://github.com/gruntwork-io/terragrunt
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Automatically load account-level variables
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))

  # Automatically load region-level variables
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  # Automatically load environment-level variables
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))

  # Extract the variables we need for easy access
  account_name = local.account_vars.locals.account_name
  account_id   = local.account_vars.locals.aws_account_id
  aws_region   = local.region_vars.locals.aws_region

  # Same pattern as ~/projects/hegarty/eks/root.hcl. $MODULE_SOURCE (a local
  # checkout of the terraform repo) is the normal path for local iteration;
  # unset, this resolves to the real tagged-module git source.
  remote_source = "git::ssh://git@github.com/hegarty/terraform.git"
  module_source = get_env("MODULE_SOURCE") != null ? "${get_env("MODULE_SOURCE")}/%s" : "${local.remote_source}//%s"
}

# Generate an AWS provider block
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Only these AWS Account IDs may be operated on by this template
  allowed_account_ids = ["${local.account_id}"]
}
EOF
}

# eks-prod lives in its OWN AWS account (868150784168, see account.hcl) —
# separate from eks-dev's account, so it needs its own state bucket and lock
# table in that account. Neither exists yet; bootstrap them once by hand
# before the first `terragrunt init` (see README.md) — Terragrunt/Terraform
# can't create the backend it's about to store state in.
remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = "tf-state-${local.account_name}-${local.account_id}-${local.aws_region}"
    key            = "${path_relative_to_include()}/tf.tfstate"
    region         = local.aws_region
    dynamodb_table = "tf-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# GLOBAL PARAMETERS
# These variables apply to all configurations in this subfolder. These are automatically merged into the child
# `terragrunt.hcl` config via the include block.
# ---------------------------------------------------------------------------------------------------------------------

inputs = merge(
  local.account_vars.locals,
  local.region_vars.locals,
  local.environment_vars.locals,
)
