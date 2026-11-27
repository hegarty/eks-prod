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

  # The chart's startupProbe/livenessProbe exec commands curl an admin API
  # hostname with a trailing dot (via a different template helper than the
  # postStart/preStop hooks use) - that trailing-dot form reliably fails to
  # resolve (confirmed: curl exit 6, ~9.8s) even though the identical name
  # without the dot resolves instantly. No values path exists to fix the
  # probe commands themselves, so this replaces them via postrender - see
  # fix-probes.sh for the full explanation and the actual yq logic.
  postrender_enabled     = true
  postrender_binary_path = "${get_terragrunt_dir()}/fix-probes.sh"
  postrender_args        = []

  helm_values = {
    statefulset = {
      replicas = 1

      # This one IS read by the chart template (unlike startupProbe above)
      # - keeping it for when the probe handoff reaches readiness, same
      # curl -m 5 vs. default-1s mismatch would otherwise recur there too.
      readinessProbe = { timeoutSeconds = 5 }
    }

    resources = {
      cpu    = { cores = "1" }
      # The chart allocates redpanda = 0.8 * container, plus a near-fixed
      # ~202Mi reserve on top (container must clear redpanda+reserve - rules
      # out 750Mi/1000Mi). Separately, the redpanda binary itself hard-
      # refuses to start below 1024Mi of its own allocation ("Memory: ...
      # below recommended: 1073741824") - at 0.8x that means container must
      # be >= ~1280Mi; 1200Mi (960Mi share) still failed this on its own.
      memory = { container = { max = "1500Mi", min = "1400Mi" } }
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
      # Same trailing-dot bug as the probes above, this time in Console's
      # auto-generated admin API URL - the chart merges user-supplied
      # console.config over its own generated config (user values win). The
      # path is console.console.config, not console.config - "console" here
      # is a subchart, and its OWN values schema has a nested "console" key
      # (confirmed in the subchart's template source: $consoleValue.console).
      console = {
        config = {
          redpanda = {
            adminApi = {
              enabled = true
              urls    = ["http://redpanda.redpanda.svc.cluster.local:9644"]
            }
          }
        }
      }
    }

    tls = {
      enabled = false # in-cluster only, no external listener — see docs/security.md
    }
  }
}
