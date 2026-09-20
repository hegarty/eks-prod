locals {
  account_name = "eks-prod"

  # Its own AWS account — separate from eks-dev's (891377023413). Override
  # with $EKS_PROD_ACCOUNT_ID if this ever needs to change without editing
  # committed code.
  aws_account_id = get_env("EKS_PROD_ACCOUNT_ID", "868150784168")
}
