locals {
  module_path    = "eks/addons/helm"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../cluster"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# One collector deployment (not a per-node DaemonSet — no host-metrics
# requirement yet) receiving OTLP from shop_ingestor/shop_analytics/
# shop_notifier, fanning out to Tempo (traces), Loki (logs), and Prometheus
# (metrics, via a scraped /metrics endpoint rather than remote_write).
inputs = {
  cluster_name     = dependency.cluster.outputs.cluster_name
  release_name     = "otel-collector"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  chart_version    = "0.108.0"
  namespace        = "observability"
  create_namespace = true

  helm_values = {
    mode         = "deployment"
    replicaCount = 1

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { memory = "256Mi" }
    }

    ports = {
      metrics = { enabled = true, containerPort = 8889, servicePort = 8889 }
    }

    config = {
      receivers = {
        otlp = {
          protocols = {
            grpc = { endpoint = "0.0.0.0:4317" }
            http = { endpoint = "0.0.0.0:4318" }
          }
        }
      }
      processors = {
        batch = {}
      }
      exporters = {
        "otlp/tempo" = {
          endpoint = "tempo.observability.svc.cluster.local:4317"
          tls      = { insecure = true }
        }
        "loki" = {
          endpoint = "http://loki-gateway.observability.svc.cluster.local/loki/api/v1/push"
        }
        "prometheus" = {
          endpoint = "0.0.0.0:8889"
        }
      }
      service = {
        pipelines = {
          traces = {
            receivers  = ["otlp"]
            processors = ["batch"]
            exporters  = ["otlp/tempo"]
          }
          logs = {
            receivers  = ["otlp"]
            processors = ["batch"]
            exporters  = ["loki"]
          }
          metrics = {
            receivers  = ["otlp"]
            processors = ["batch"]
            exporters  = ["prometheus"]
          }
        }
      }
    }
  }
}
