locals {
  module_path    = "secrets-manager"
  module_version = "v1.0.0"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Empty shell — the Shopify Admin API token + webhook signing secret for the
# "devmoto" tenant are set out-of-band (Shopify Partner Dashboard -> AWS
# console/CLI), never through Terraform or committed anywhere.
inputs = {
  name        = "commerce-intel/shopify/devmoto"
  description = "Shopify Admin API token + webhook signing secret for tenant devmoto. Populated out-of-band."
}
