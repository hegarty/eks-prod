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

# SingleBinary mode on a small EBS volume, not S3-backed chunks — MVP cost
# tradeoff (log volume is low at one tenant). Move to S3-backed storage +
# longer retention before this becomes a real bottleneck; see
# docs/observability.md.
inputs = {
  cluster_name     = dependency.cluster.outputs.cluster_name
  release_name     = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  chart_version    = "6.16.0"
  namespace        = "observability"
  create_namespace = true

  helm_values = {
    deploymentMode = "SingleBinary"

    loki = {
      auth_enabled = false
      commonConfig = { replication_factor = 1 }
      schemaConfig = {
        configs = [
          {
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index        = { prefix = "index_", period = "24h" }
          }
        ]
      }
      limits_config = {
        retention_period = "72h"
      }
    }

    singleBinary = {
      replicas = 1
      resources = {
        requests = { cpu = "50m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
      persistence = {
        enabled      = true
        storageClass = "gp3"
        size         = "10Gi"
      }
    }

    # Disable the chart's other deployment-mode components — SingleBinary
    # covers everything at this scale.
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    backend = { replicas = 0 }
    gateway = { enabled = true, resources = { requests = { cpu = "10m", memory = "32Mi" } } }
  }
}
