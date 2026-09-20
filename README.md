# eks-prod

Terragrunt configuration for a dedicated, shared EKS cluster (`eks-prod`) — separate from
the personal-lab `eks-dev` cluster in [`hegarty/eks`](https://github.com/hegarty/eks).

This cluster is deliberately **not** scoped to a single project. It's built once, with
Cilium (Gateway API, Hubble, default-deny NetworkPolicy), Karpenter, and a self-hosted
observability stack (Prometheus/Grafana/Loki/Tempo/OTel Collector), so its fixed costs
(EKS control plane, NAT Gateway) amortize across whatever unrelated workloads land on it
over time — not just the first one.

## Layout

```
account.hcl, env.hcl, root.hcl   # same conventions as ~/projects/hegarty/eks
us-east-1/
  networking/                    # VPC, IGW, single NAT Gateway, routes, security group
  eks/                           # cluster, IAM, Karpenter, storage class, access entries,
                                  # addons (Cilium, cert-manager, Redpanda, observability)
  workloads/
    commerce-intel/              # THIS project's own AWS resources only: RDS, S3 raw
                                  # archive, ECR repos, Secrets Manager shells, Pod
                                  # Identity roles, budget. A future unrelated project
                                  # gets its own sibling directory here — it does not
                                  # touch anything under us-east-1/eks or networking/.
manifests/karpenter/              # NodePool/EC2NodeClass — applied via kubectl, not
                                  # Terraform (see docs/deployment.md)
```

Reusable Terraform modules live in [`hegarty/terraform`](https://github.com/hegarty/terraform),
referenced by immutable tag (`<module-path>/vX.Y.Z`) — see that repo's README for the
versioning convention.

## AWS account

Lives in its own AWS account — **868150784168** — separate from `eks-dev`'s account
(891377023413). `account.hcl` defaults to that ID; override with `$EKS_PROD_ACCOUNT_ID` if
it ever needs to change without editing committed code. Because it's a different account,
state can't reuse `eks-dev`'s S3 bucket/DynamoDB table — this repo needs its own.

You'll also need an AWS CLI profile/SSO session authenticated against 868150784168 to run
any of this (e.g. `AWS_PROFILE=eks-prod`). The generated provider block's
`allowed_account_ids` will hard-refuse to apply against any other account, including
eks-dev's, as a safety net against a mismatched profile.

**Before the first `terragrunt init`**, `us-east-1/eks/access_entries/users/terragrunt.hcl`
still has a placeholder `principal_arn` (`REPLACE_ME_ADMIN_ROLE`) — eks-dev's admin role
doesn't exist in this account. Replace it with the SSO/IAM role you'll actually administer
this cluster with.

## Bootstrapping remote state (one-time, run by hand — not something Terragrunt can do for
## itself)

Neither the state bucket nor the lock table exist yet in 868150784168. Create them once,
using credentials for that account:

```bash
export AWS_PROFILE=eks-prod   # or however you've named the profile for 868150784168
REGION=us-east-1
ACCOUNT_ID=868150784168
BUCKET="tf-state-eks-prod-${ACCOUNT_ID}-${REGION}"

aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table \
  --table-name tf-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION"
```

Verify both exist before running `terragrunt init` anywhere in this repo — Terragrunt will
otherwise fail trying to configure a backend that isn't there.

## Deploying

See `docs/deployment.md` (in `shop_docs`) for the ordered command sequence. Nothing here
has been applied yet — Terragrunt units reference tagged module versions that must be
released from the terraform repo first.
