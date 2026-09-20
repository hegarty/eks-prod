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

# Self-hosted, not AMP/AMG — see docs/observability.md and ADR-009. Short
# local retention is a deliberate cost control, not an oversight.
inputs = {
  cluster_name     = dependency.cluster.outputs.cluster_name
  release_name     = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  chart_version    = "66.3.1"
  namespace        = "observability"
  create_namespace = true
  timeout_seconds  = 900

  helm_values = {
    prometheus = {
      prometheusSpec = {
        retention = "3d"
        resources = {
          requests = { cpu = "100m", memory = "512Mi" }
          limits   = { memory = "1Gi" }
        }
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "gp3"
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "10Gi" } }
            }
          }
        }
      }
    }

    alertmanager = {
      enabled = true
      alertmanagerSpec = {
        resources = { requests = { cpu = "10m", memory = "32Mi" } }
      }
    }

    grafana = {
      enabled = true
      # No adminPassword here — populated from a manually-created k8s Secret
      # (see docs/deployment.md), never committed to Git.
      admin = {
        existingSecret = "grafana-admin-credentials"
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }
      persistence = {
        enabled          = true
        storageClassName = "gp3"
        size             = "2Gi"
      }
      resources = {
        requests = { cpu = "25m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
      additionalDataSources = [
        {
          name   = "Loki"
          type   = "loki"
          url    = "http://loki-gateway.observability.svc.cluster.local"
          access = "proxy"
        },
        {
          name   = "Tempo"
          type   = "tempo"
          url    = "http://tempo.observability.svc.cluster.local:3100"
          access = "proxy"
        },
      ]
    }

    kubeControllerManager = { enabled = false } # not reachable on EKS (managed control plane)
    kubeScheduler         = { enabled = false }
    kubeEtcd              = { enabled = false }

    nodeExporter = {
      resources = { requests = { cpu = "25m", memory = "32Mi" } }
    }

    kubeStateMetrics = {
      resources = { requests = { cpu = "25m", memory = "64Mi" } }
    }
  }
}
