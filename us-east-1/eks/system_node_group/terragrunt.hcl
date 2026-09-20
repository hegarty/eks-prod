locals {
  module_path    = "eks/node_group"
  module_version = "v1.0.0"
}

dependency "cluster" {
  config_path = "../cluster"
}

dependency "iam" {
  config_path = "../iam/node_role"
}

dependency "vpc" {
  config_path = "../../networking/vpc"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

# One small static node group to bootstrap the cluster before Karpenter can
# run itself: Karpenter controller, Cilium operator + agent DaemonSet,
# CoreDNS, cert-manager. Everything else (app workloads, most of
# observability) is scheduled onto Karpenter-managed nodes.
inputs = {
  name           = "eks-prod-system"
  instance_types = ["t4g.medium"]
  ami_type       = "AL2023_ARM_64_STANDARD"
  capacity_type  = "ON_DEMAND"

  block_device_mappings = [{
    device_name = "/dev/xvda"
    ebs = {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }]

  metadata_options = [{
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }]

  # Private worker subnets behind the single NAT — no public IPs.
  associate_public_ip_address = false

  node_role_arn = dependency.iam.outputs.arn
  vpc_id        = dependency.vpc.outputs.vpc_id
  subnet_ids    = dependency.vpc.outputs.worker_subnets
  cluster_name  = dependency.cluster.outputs.cluster_name

  scaling_desired_size = 1
  scaling_max_size     = 1
  scaling_min_size     = 1

  user_data = <<EOF
  #!/bin/bash
  set -ex
  /etc/eks/bootstrap.sh ${dependency.cluster.outputs.cluster_name} \
  --b64-cluster-ca ${dependency.cluster.outputs.certificate-authority[0].data} \
  --apiserver-endpoint ${dependency.cluster.outputs.api-server-endpoint} \
  EOF
}
