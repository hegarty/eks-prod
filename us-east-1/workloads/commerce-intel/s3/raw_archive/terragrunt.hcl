locals {
  module_path    = "s3"
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
  bucket_name        = "commerce-intel-raw-archive-${include.root.locals.account_id}"
  versioning_enabled = true
  force_destroy      = false

  # Raw Shopify payloads are cheap, durable, replay-source-of-truth archive —
  # not something queried often. Push to IA quickly, Glacier after a quarter.
  # See docs/cost-model.md and docs/disaster-recovery.md.
  lifecycle_rules = [
    {
      id      = "raw-archive-tiering"
      enabled = true
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER" },
      ]
    }
  ]

  tags = {
    Environment = "prod"
    Project     = "commerce-intel"
    Purpose     = "raw-event-archive"
  }
}
