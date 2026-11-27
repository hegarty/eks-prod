locals {
  module_path    = "eks/addons/helm"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../cluster"
}

# storage_class has no outputs of its own (it's just a kubernetes_storage_class_v1
# resource) - a plain `dependency` block fails Terragrunt's output resolution for
# a zero-output target, so this is ordering-only via `dependencies`.
dependencies {
  paths = ["../../storage_class"]
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Single-binary Tempo on a small EBS volume, short trace retention — same
# MVP cost tradeoff as Loki. See docs/observability.md.
inputs = {
  cluster_name     = dependency.cluster.outputs.cluster_name
  release_name     = "tempo"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  chart_version    = "1.13.0"
  namespace        = "observability"
  create_namespace = true

  helm_values = {
    tempo = {
      retention = "24h"
      storage = {
        trace = {
          backend = "local"
        }
      }
    }

    persistence = {
      enabled          = true
      storageClassName = "gp3"
      size             = "10Gi"
    }

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }
  }
}
