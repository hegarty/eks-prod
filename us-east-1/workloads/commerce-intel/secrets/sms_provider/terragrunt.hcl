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

# Empty shell — the SMS vendor API key is set out-of-band once shop_notifier's
# vendor adapter is built and a vendor is chosen.
inputs = {
  name        = "commerce-intel/sms-provider"
  description = "SMS provider (vendor TBD) API credentials for shop_notifier. Populated out-of-band."
}
