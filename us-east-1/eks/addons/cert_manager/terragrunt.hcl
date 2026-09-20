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

inputs = {
  cluster_name     = dependency.cluster.outputs.cluster_name
  release_name     = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  chart_version    = "v1.16.2"
  namespace        = "cert-manager"
  create_namespace = true

  helm_values = {
    installCRDs = true
    resources = {
      requests = { cpu = "25m", memory = "64Mi" }
      limits   = { memory = "128Mi" }
    }
    webhook = {
      resources = { requests = { cpu = "10m", memory = "32Mi" } }
    }
    cainjector = {
      resources = { requests = { cpu = "10m", memory = "64Mi" } }
    }
  }
}
