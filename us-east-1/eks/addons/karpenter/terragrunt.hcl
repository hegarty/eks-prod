locals {
  module_path    = "eks/addons/helm"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../../cluster"
}

dependency "karpenter_iam" {
  config_path = "../../karpenter"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# Apply after eks/system_node_group and eks/karpenter (IAM/SQS) exist. The
# controller pod authenticates via EKS Pod Identity (associated directly by
# the eks/karpenter module) — no IRSA annotation needed on the ServiceAccount.
# After this installs, apply eks/manifests/karpenter/*.yaml to give it
# something to actually provision against.
inputs = {
  cluster_name  = dependency.cluster.outputs.cluster_name
  release_name  = "karpenter"
  repository    = "oci://public.ecr.aws/karpenter/karpenter"
  chart         = "karpenter"
  chart_version = "1.0.8"
  namespace     = "kube-system"

  helm_values = {
    settings = {
      clusterName       = dependency.cluster.outputs.cluster_name
      clusterEndpoint   = dependency.cluster.outputs["api-server-endpoint"]
      interruptionQueue = dependency.karpenter_iam.outputs.interruption_queue_name
    }

    serviceAccount = {
      name = "karpenter"
    }

    replicas = 1

    resources = {
      requests = { cpu = "100m", memory = "256Mi" }
      limits   = { memory = "512Mi" }
    }

    # Karpenter itself must run on the static system node group, not on
    # nodes it launches — avoids a chicken-and-egg outage on restart.
    tolerations = [
      { key = "CriticalAddonsOnly", operator = "Exists" }
    ]
  }
}
