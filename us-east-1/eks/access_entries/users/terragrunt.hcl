locals {
  module_path    = "eks/access_entries/users"
  module_version = "v1.0.0"
}

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = format(include.root.locals.module_source, "${local.module_path}?ref=${local.module_path}/${local.module_version}")
}

inputs = {
  cluster_name = "eks-prod"

  # PLACEHOLDER — eks-dev's admin ARN (account 891377023413) does not exist in
  # this account (868150784168) and will NOT apply. Replace with the
  # SSO/IAM role you'll actually use to administer this cluster, e.g.:
  #   aws sts get-caller-identity --profile <eks-prod-profile>
  #   aws iam list-roles --profile <eks-prod-profile> | grep -i sso
  principal_arn     = "arn:aws:iam::868150784168:role/REPLACE_ME_ADMIN_ROLE"
  policy_arn        = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope_type = "cluster"
}
