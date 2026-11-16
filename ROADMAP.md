# Roadmap

Account-scoped roadmap for this repo. This feeds into, and should be read
alongside, the **master org-wide roadmap**:
[`hegarty/landingzone`'s `ROADMAP.md`, Phase 3](https://github.com/hegarty/landingzone/blob/main/ROADMAP.md#phase-3--centralized-network-ingressegress--inspection-inside-out-rollout)
— that file has the full, multi-account picture (why, cost shape, and how
every member account eventually fits together); this file has only what's
specific to standing up and running *this* account.

## Strategy: this account ships first, independent of the org-wide network work

The org-wide plan is explicitly inside-out: get real business value flowing
through `eks-prod` (the `commerce-intel`/Shopify integration) on this
account's own, already-designed, standalone NAT Gateway/IGW — no dependency
on the shared `networking` account, Transit Gateway, or the Suricata
inspection layer described in `landingzone`'s roadmap. Those are later
milestones there, not blockers here.

## Milestone 1 (current) — Go live on standalone ingress/egress

Nothing in this repo has been applied yet. Outstanding, in dependency order:

1. **AWS profile for account `868150784168`** — not yet configured locally.
   Add an SSO profile (`sso_account_id = 868150784168`, `sso_role_name =
   org-admin`) alongside this machine's existing `tsh-root`/`tsh-eks`
   profiles, then `aws sso login`.
2. **Replace the placeholder admin ARN** —
   `us-east-1/eks/access_entries/users/terragrunt.hcl`'s `principal_arn` is
   still `REPLACE_ME_ADMIN_ROLE`. Needs the real SSO-managed role ARN for
   this account once (1) is live.
3. **Bootstrap remote state** — the S3 bucket + DynamoDB lock table for this
   account don't exist yet. Commands are in this repo's own `README.md`.
4. **Tag the remaining Terraform modules** this repo's units reference but
   that aren't yet tagged in `hegarty/terraform`: `eks/karpenter`,
   `eks/pod_identity`, `rds-postgres`, `secrets-manager`, `budgets`
   (`make release MODULE=<path> VERSION=1.0.0` in that repo).
5. **First real bring-up via `eks-lifecycle`** —
   `./eks-lifecycle doctor` → `./eks-lifecycle plan up` (review) →
   `./eks-lifecycle up --plan <dir>`. `eks-lifecycle` itself is fully built
   and locally validated but has never been pushed to GitHub — worth doing
   before this, not required by it.
6. **Build the missing application layer** — `shop_ingestor`,
   `shop_analytics`, `shop_notifier` have no Helm charts/Kubernetes
   manifests yet (`status: not_ready` in `eks-lifecycle`'s `lifecycle.yaml`;
   explicitly deferred "back burner" work per `shop_docs`). Needed before any
   of the three can actually run on this cluster.
7. **Register the real Shopify webhook** against the `devmoto` store, once
   `shop_ingestor` is deployed and reachable — per
   `shop_docs/docs/deployment.md` step 6, run by the user, never
   automatically.

## Milestone 2 (future) — Cut over to centralized ingress/egress

Once `landingzone`'s Phase 3 networking/inspection hub exists and is proven
(its own milestones 2-3), migrate this account's egress from its standalone
NAT Gateway/IGW onto the shared hub via a new Transit Gateway attachment,
then retire the standalone NAT Gateway. Not started; not blocking Milestone
1 in either direction.
