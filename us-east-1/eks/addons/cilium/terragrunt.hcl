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

# Apply this AFTER eks/system_node_group exists (Cilium's agent DaemonSet
# needs a node to schedule onto) — see the deployment runbook for ordering.
# Overlay (VXLAN) networking + cluster-pool IPAM: simplest mode on EKS, avoids
# ENI IP exhaustion and the extra IAM permissions native/ENI mode needs.
# kube-proxy is fully replaced by Cilium (kubeProxyReplacement).
inputs = {
  cluster_name  = dependency.cluster.outputs.cluster_name
  release_name  = "cilium"
  repository    = "https://helm.cilium.io/"
  chart         = "cilium"
  chart_version = "1.16.5"
  namespace     = "kube-system"

  helm_values = {
    kubeProxyReplacement = true
    k8sServiceHost       = replace(dependency.cluster.outputs["api-server-endpoint"], "https://", "")
    k8sServicePort       = 443

    tunnelProtocol = "vxlan"
    ipam = {
      mode = "cluster-pool"
      operator = {
        clusterPoolIPv4PodCIDRList = ["10.244.0.0/16"]
        clusterPoolIPv4MaskSize    = 24
      }
    }

    operator = {
      replicas = 1
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
    }

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "512Mi" }
    }

    hubble = {
      enabled = true
      relay   = { enabled = true, resources = { requests = { cpu = "50m", memory = "64Mi" } } }
      ui      = { enabled = true, resources = { requests = { cpu = "25m", memory = "32Mi" } } }
    }

    # Cilium's own Gateway API support — the one external NLB in front of
    # shop_ingestor's Shopify webhook endpoint is provisioned through this.
    gatewayAPI = {
      enabled = true
    }

    # Enforced default-deny is applied via CiliumNetworkPolicy manifests
    # (eks/manifests/network-policies/), not a Helm value — see
    # docs/security.md for the explicit allow-list per workload.
  }
}
