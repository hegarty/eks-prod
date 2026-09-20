locals {
  module_path    = "eks/addons/helm"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../cluster"
}

dependency "storage_class" {
  config_path = "../../storage_class"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Single broker — deliberate MVP availability tradeoff (see ADR-005). Not the
# source of truth: raw events are archived to S3 and Postgres holds
# normalized state, so a lost broker is rebuildable via reconciliation, not a
# data-loss event. Revisit before onboarding a second tenant that can't
# tolerate ingestion downtime.
inputs = {
  cluster_name     = dependency.cluster.outputs.cluster_name
  release_name     = "redpanda"
  repository       = "https://charts.redpanda.com/"
  chart            = "redpanda"
  chart_version    = "5.9.14"
  namespace        = "redpanda"
  create_namespace = true
  timeout_seconds  = 900

  helm_values = {
    statefulset = {
      replicas = 1
    }

    resources = {
      cpu    = { cores = "1" }
      memory = { container = { max = "1500Mi", min = "750Mi" } }
    }

    storage = {
      persistentVolume = {
        enabled      = true
        storageClass = "gp3"
        size         = "20Gi"
      }
    }

    config = {
      cluster = {
        # A single node can't replicate — set factors to 1 so topic creation
        # doesn't demand brokers that don't exist.
        "default_topic_replications"        = 1
        "internal_topic_replication_factor" = 1
      }
    }

    console = {
      enabled = true
      resources = {
        requests = { cpu = "25m", memory = "64Mi" }
      }
    }

    tls = {
      enabled = false # in-cluster only, no external listener — see docs/security.md
    }
  }
}
