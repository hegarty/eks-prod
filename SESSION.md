# SESSION.md — running context for Claude

Read this first if picking up this project cold. This cluster went from
"nothing applied" to a mostly-healthy, real bring-up in one long session
(2026-11-22 through 2026-11-27) — almost every real bug below was found by
actually running `eks-lifecycle` against live AWS, not by code review. Full
blow-by-blow is in the conversation history; this file is the durable
summary.

## What this project is

Terragrunt config for `eks-prod` — a dedicated, shared EKS cluster (account
`868150784168`), built to host `commerce-intel` and future unrelated
workloads. See `README.md` for the architecture/layout and `ROADMAP.md` for
the account-level plan (and its link to `hegarty/landingzone`'s Phase 3 for
the org-wide centralized-ingress/egress picture — a separate, not-yet-started
initiative).

Brought up and operated via [`hegarty/eks-lifecycle`](https://github.com/hegarty/eks-lifecycle)
(a separate repo, still local-only — never pushed to GitHub). See that
repo's own `SESSION.md` for the orchestrator-level bug found and fixed
during this same session.

## Current infrastructure state (as of 2026-11-27)

**Live and healthy**: VPC/networking, EKS cluster (`eks-prod`, k8s 1.37),
IAM, security groups, static system node group (`t4g.xlarge`, resized up
from `t4g.medium`), Cilium, cert-manager, `eks-pod-identity-agent`,
`aws-ebs-csi-driver`, gp3 StorageClass, Karpenter (controller + CRDs —
**actually working**, see note below), `kube-prometheus-stack`
(Prometheus/Grafana/Alertmanager), Loki, OTel Collector, and **the full
Redpanda stack — broker and console both**. `redpanda-console` was broken
for the entire 2026-11-22→2026-11-27 span (1,383 restarts at its worst) —
see "Resolved" below for the real root cause and fix, found via a genuine
cross-node Cilium/security-group investigation, not a chart bug.

**Not yet reached**: `access_entries/karpenter_node` and anything
downstream of it in the dependency graph — `resume` was blocked on
`redpanda` this entire time and hasn't been re-run since the fix landed.

**Correction to an earlier wrong call, recorded here so it isn't repeated**:
this session initially concluded "no published Karpenter version supports
this cluster's k8s 1.37" and deliberately abandoned dynamic node scaling in
favor of relying solely on the static node group. That conclusion was
**wrong** — Karpenter does provision real nodes on this cluster today (a
second node, `eks-prod-default-qc9dx`, was launched by it and is
`registered: true` / `initialized: true`). The `providers.version`
reconciler's "karpenter is not compatible with kubernetes version" error is
apparently non-fatal and doesn't block core provisioning. Karpenter chart
version is currently pinned at `1.6.1` (bumped twice today, from `1.0.8`).
Don't re-litigate "Karpenter can't work here" without re-checking first.

## Resolved: redpanda-console's real root cause was never DNS — it was a security-group mismatch splitting the node fleet

What looked like a CoreDNS/`ndots` problem for most of this investigation
turned out, once traced all the way through, to be a completely different
layer: **Karpenter-launched nodes and the static system node group's node
were in two different, mutually-untrusting AWS security groups**, so pods
split across them could not reach each other over the network *at all* —
no DNS resolution, no raw IP connectivity, nothing. Every earlier DNS-shaped
symptom (bare Service names not resolving, a missing `EndpointSlice`) was a
downstream consequence of this, or in one case an artifact of investigating
a Helm release (`atomic = true`) that had already rolled itself back
mid-investigation — not a real, separate bug. Record of the full dead-end
and how it was ruled out is kept below for anyone re-deriving this; don't
repeat the DNS/`ndots` detour.

**The actual mechanism**:
- Karpenter's `EC2NodeClass` (`manifests/karpenter/ec2nodeclass.yaml`)
  selects security groups by tag: `securityGroupSelectorTerms: [{tags:
  {karpenter.sh/discovery: eks-prod}}]`. Only the custom, narrow SG this
  repo created (`us-east-1/eks/security_groups`, ingress limited to TCP
  443/10250 from the VPC CIDR) carried that tag.
- The static system node group's node uses a *different* SG entirely — the
  one EKS auto-creates per cluster (`vpc_config.cluster_security_group_id`,
  not something this repo's Terraform directly manages as a resource). That
  SG has one rule: all protocols/ports, self-referencing (`UserIdGroupPairs`
  → itself) — the standard AWS default, specifically meant to let
  control-plane/node/node traffic flow freely.
- Since Karpenter nodes were never members of that SG, that rule never
  covered them, and the narrow SG they *were* in had no VXLAN (UDP 8472)
  rule, nor anything referencing the other SG. Pods on nodes split across
  the two SGs were completely unreachable from each other — not flaky, not
  rate-limited, just structurally blocked at the ingress boundary on
  whichever side received the packet.
- Confirmed directly and precisely, in order: `cilium status`'s own
  `Cluster health: 1/2 reachable` (Cilium's built-in cross-node agent
  health-check, over the same VXLAN path real pod traffic uses) named the
  exact unreachable node; `aws ec2 describe-instances`/`describe-security-groups`
  then showed the two nodes' actual attached SGs and rules directly, no
  inference required.

**The fix**: tag the EKS-managed cluster security group with
`karpenter.sh/discovery = eks-prod` too, so Karpenter's existing selector
matches both SGs going forward. Implemented via a new `aws_ec2_tag` resource
in `hegarty/terraform`'s `eks/cluster` module (can't tag that SG via the
`aws_eks_cluster` resource's own `tags` block — AWS creates it as a side
effect, not something this module directly owns) — see that repo's own
changes below. Wired in via a new `cluster_security_group_tags` input on
`eks-prod`'s `us-east-1/eks/cluster/terragrunt.hcl`.

**What happened next, worth understanding as a Karpenter mechanism in its
own right**: tagging the SG does *not* retroactively reach already-running
EC2 instances — `securityGroupSelectorTerms` is only evaluated at launch
time. Nothing needed to be manually forced, though: Karpenter's **drift**
detection (one of its three built-in disruption mechanisms, alongside
expiration and consolidation) noticed that every existing `NodeClaim`'s
actual attached SGs no longer matched what a fresh launch would now
produce, and automatically replaced the *entire* Karpenter-managed fleet
(three nodes, all simultaneously) with no manual `kubectl delete nodeclaim`
needed. Confirmed directly via each new `NodeClaim`'s own Events:
`DisruptionLaunching ... Launching NodeClaim: Drifted`. Post-fix
verification: `aws ec2 describe-instances` on a freshly-launched node shows
both SGs attached; `cilium status` reports `Cluster health: 4/4 reachable`;
`redpanda-console` went to `1/1 Running` on the very next attempt after
1,383 prior restarts.

**The DNS/`ndots` dead end, for the record** (don't re-investigate this —
it was real evidence, pointing at the wrong layer, not a mistake to avoid
repeating methodologically):
- Per-pod StatefulSet DNS names (`redpanda-0.redpanda.redpanda.svc.cluster.local`)
  always resolved instantly — unsurprising in hindsight, since
  `redpanda-console` was never actually trying to reach a *different* node
  until it used the bare Service name.
- The bare headless-Service name (`redpanda.redpanda.svc.cluster.local`)
  returned an **authoritative NXDOMAIN** at one point — not a timeout, a
  confident "doesn't exist" from CoreDNS itself (`status: NXDOMAIN`, `aa`
  flag set, zone SOA in the `AUTHORITY` section). That specific result
  traced back to a vanished `EndpointSlice` — because the Helm release
  backing it had already fully uninstalled itself (`atomic = true`) while
  we were investigating; `helm list -n redpanda -a` came back completely
  empty mid-investigation. Lesson: confirm the thing you're debugging still
  exists before trusting evidence gathered minutes apart against it,
  especially with `atomic = true` in play.
- Raw IP connectivity (bypassing DNS entirely) timed out identically
  (`curl` exit 28, ~5.0s) on a *separately re-confirmed-stable* release —
  that's what actually ruled DNS out and pointed at the network layer
  underneath it instead.

## Real bugs found and fixed this session

All were genuine pre-existing issues, surfaced only by actually running
`eks-lifecycle` against real AWS — not introduced by this session's work.

**In `eks-prod` (this repo) — Terragrunt unit config:**
- `access_entries/users`, `access_entries/nodes` — missing `dependency` on
  `eks/cluster` (both now fixed; `nodes`'s policy-association logic also
  needed to become conditional, since `EC2_LINUX`-type access entries don't
  support policy associations at all — AWS rejects it outright).
- `addons/karpenter` — `repository` had a duplicated OCI path segment
  (`.../karpenter/karpenter` instead of `.../karpenter`).
- `addons/karpenter_crds` — **new unit**, didn't exist before. Karpenter
  ships CRDs as a separate chart from the controller; nothing installed
  them.
- `addons/pod_identity_agent` — **new unit**. The `eks-pod-identity-agent`
  EKS add-on was never installed at all, so Karpenter's (and everything
  else's) Pod Identity associations were inert — `NoCredentialProviders`.
- `addons/ebs_csi/{role,addon}` — **new units**. `aws-ebs-csi-driver` was
  never installed either. Every `storageClassName: gp3` PVC
  (`kube-prometheus-stack`, `loki`, `redpanda`) was stuck in
  `ExternalProvisioning` forever until this landed.
- `addons/kube_prometheus_stack`, `addons/loki`, `addons/redpanda`,
  `addons/tempo` — all four declared a `dependency "storage_class"` purely
  for ordering, but that module has zero outputs, which this Terragrunt
  version can't resolve at all (not even "not applied yet" — a hard
  parse-time failure). Converted to a `dependencies { paths = [...] }`
  block (ordering-only, no output resolution).
- `addons/loki` — missing `loki.storage.type = "filesystem"`. The chart's
  default is `s3` regardless of `schemaConfig.object_store`; without this,
  a template helper nil-panics on `bucketNames.chunks`.
- `addons/otel_collector` — missing `image.repository`. This chart
  stopped shipping a default; without it, nothing renders at all. Set to
  `otel/opentelemetry-collector-contrib` (the plain `otel/opentelemetry-collector`
  "core" image doesn't include the `loki` exporter this config uses).
- `addons/redpanda` — three independent, stacked issues, all now fixed:
  1. `resources.memory.container.min` (`750Mi` → `1400Mi`): the chart
     allocates `redpanda = 0.8 × container` plus a near-fixed ~202Mi
     reserve, **and** the redpanda binary itself hard-refuses to start
     below 1024Mi of its own allocation. `container` must clear ~1280Mi
     for the 80% share to exceed that floor.
  2. `startupProbe`/`livenessProbe` exec commands curl an admin-API
     hostname with a trailing dot, which reliably fails to resolve
     (confirmed: `curl` exit 6, ~9.8s) even though the identical name
     without the dot resolves instantly — an internal chart
     inconsistency (the postStart/preStop hooks build the *same* URL
     *without* the trailing dot and work fine). No values path exists to
     fix the probe commands, so `fix-probes.sh` (new file, this unit's
     directory) replaces them via Helm's `postrender` hook with a plain
     `curl localhost:9644` check instead.
  3. `redpanda-console`'s admin URL has the *same* trailing-dot bug, fixed
     via `helm_values.console.console.config.redpanda.adminApi.urls`
     (note the double-nested `console.console` — "console" is a subchart
     whose own values schema also has a top-level `console` key; confirmed
     directly in the subchart's template source). This fix is what
     surfaced the separate CoreDNS/ndots issue above (the dot-less URL
     this override uses is the *bare Service name*, which is the thing
     that isn't resolving).
- `system_node_group` — resized `t4g.medium` → `t4g.xlarge` (Karpenter
  itself couldn't reliably start on the smaller instance — zero log
  output, both liveness/readiness probes timing out, consistent with CPU
  starvation on an already-dense node).

**In `hegarty/terraform` (shared modules) — real bugs, not just config:**
- `eks/access_entries/users/main.tf`, `eks/access_entries/nodes/main.tf` —
  missing `depends_on`/conditional logic (see above).
- `eks/addons/aws/variables.tf` — `service_role_arn` had no default,
  forcing every caller to provide an IAM role even for add-ons
  (`eks-pod-identity-agent`) that genuinely need none. Made optional.
- `eks/addons/helm/main.tf` — `postrender_enabled`/`postrender_binary_path`/
  `postrender_args` were declared as input variables but **never actually
  wired into the `helm_release` resource** — completely dead code until
  this session added the `dynamic "postrender"` block.
- `eks/node_group/main.tf` — `node_group_name` was a fixed string with no
  `lifecycle { create_before_destroy = true }`. Changing `instance_types`
  therefore forced a destroy-then-create replacement — on a
  single-node-only cluster, a real (if brief) total outage. Fixed: switched
  to `node_group_name_prefix` (required for the overlap window) +
  `create_before_destroy = true`.
- `eks/addons/helm/main.tf` provider blocks — both `provider "kubernetes"`
  and `provider "helm" { kubernetes { ... } }` used a static
  `token = data.aws_eks_cluster_auth.this.token`, frozen into the plan at
  read time. EKS auth tokens are valid 15 minutes; any `helm_release` that
  runs longer than that (several did, chasing the redpanda bugs above) can
  have its token expire *mid-apply*, failing with "the server has asked for
  the client to provide credentials" — nothing to do with the chart itself.
  Fixed: replaced with an `exec` block (`aws eks get-token`), which
  regenerates a fresh token on every actual API call instead of reusing one
  frozen at plan time. This was a real, reproduced failure, not a
  theoretical risk — hit it directly on a `redpanda` apply that ran ~16
  minutes end to end.
- `eks/cluster/{main,variables,outputs}.tf` — added a
  `cluster_security_group_tags` input (default `{}`) and an `aws_ec2_tag`
  resource tagging `aws_eks_cluster.this.vpc_config[0].cluster_security_group_id`,
  plus a new `cluster_security_group_id` output. Not a bug fix in the usual
  sense — net-new capability needed to resolve the Karpenter/security-group
  mismatch described under "Resolved" above. `eks-prod`'s
  `us-east-1/eks/cluster/terragrunt.hcl` now sets
  `cluster_security_group_tags = { "karpenter.sh/discovery" = "eks-prod" }`.
- Untracked `metrics/` directory exists in this repo (`grafana/`,
  `prometheus/` module stubs) — **not created by this session**, origin
  unknown, left untouched.

**In `eks-lifecycle` itself**: see that repo's own `SESSION.md` — the
`determineResumePoint` bug (trusted S3 object *existence* instead of a real
plan result) is the single most consequential finding of this whole
session, since it's what caused several "fixed the bug but resume skipped
retrying it anyway" false starts before it was found and fixed.

## Known gap: container logs and Kubernetes Events are not captured anywhere durable

Neither is shipped into Loki (or anywhere else) today. Found while trying
to retroactively review logs from nodes Karpenter had already cycled out
during this session's investigation — they're genuinely gone, not just
hard to find.

- **Container logs**: `kubectl logs` reads ephemeral, node-local files via
  the kubelet API — nothing ships them anywhere durable. Loki is purely a
  storage/query backend; something else has to actively collect and push
  to it. The OTel Collector (`addons/otel_collector`) is deployed and *is*
  already on the `contrib` image (chosen for its `loki` exporter), but its
  only receiver is `otlp` — it only forwards logs an application explicitly
  pushes to it. Nothing deployed today does that. Closing this needs a
  `filelog` receiver reading node-local container log files, which in turn
  needs the collector running as a `DaemonSet` with host log directories
  mounted — a real shape change from its current single-replica
  `Deployment` mode, not just a config tweak.
- **Kubernetes Events** (e.g. the `DisruptionLaunching: Drifted` Events
  that were the actual proof behind this session's Karpenter/SG
  investigation): a completely separate mechanism from container logs —
  Events live only in the Kubernetes API/etcd, default ~1hr retention,
  never written to any file at all. Needs its own purpose-built watcher —
  the OTel Collector Contrib's `k8sobjects` receiver, or a dedicated tool
  like `kubernetes-event-exporter` — feeding the same already-wired
  `logs → loki` pipeline.

Neither is implemented. Flagging as a real, concrete gap (not hypothetical)
given how much of this session's own debugging depended on catching
ephemeral state before it disappeared.

## Commit/PR history — everything from this session is now merged

All of it landed as separate, scoped PRs (reviewed and merged 2026-11-27-28),
not one giant commit — each one independently reviewable, matching how
these bugs were actually found and fixed one at a time:
- `hegarty/eks-prod`: #8 (`access_entries` dependency ordering), #9
  (Karpenter CRD chart/OCI path/AMI selector), #10 (`eks-pod-identity-agent`
  + `aws-ebs-csi-driver`), #11 (node group resize), #12 (cluster SG
  tagging), #13 (observability + messaging addon fixes).
- `hegarty/terraform`: #13 (`access_entries` module fixes), #14
  (`service_role_arn` optional), #15 (`node_group` `create_before_destroy`),
  #16 (`cluster_security_group_tags`), #17 (`helm` module `postrender` +
  `exec`-based auth).
- `hegarty/eks-lifecycle`: two plain commits (no remote, no PR flow) — the
  `resume.go` fix/tests, and the ADR update recording the Redpanda
  data-durability gap.

Every cross-repo pair (the three above that touch both `eks-prod` and
`hegarty/terraform`) merged `hegarty/terraform`'s half first, matching
consumption order — though `$MODULE_SOURCE` makes this moot for local
iteration, it matters for anyone doing a clean checkout later.

## Next steps

1. Re-run `eks-lifecycle resume` now that `redpanda` (broker + console) is
   genuinely healthy and everything is committed — should continue through
   `access_entries/karpenter_node` and whatever comes after. Re-verify the
   graph rather than assume the previously-known order still holds; the
   node fleet has cycled several times since this was last checked.
2. Decide whether to close the container-log/Kubernetes-Events observability
   gap now (see above) or defer it — it's real, but net-new scope, not a
   blocker for anything currently in progress.
3. None of the five Terraform modules `eks-prod` references
   (`eks/karpenter`, `eks/pod_identity`, `rds-postgres`, `secrets-manager`,
   `budgets`) are tagged in `hegarty/terraform` yet — harmless today since
   `$MODULE_SOURCE` makes `?ref=` inert for local iteration, but worth
   doing before anyone relies on a clean checkout without that env var set.
4. Once things are stable, decide whether to actually push `eks-lifecycle`
   to GitHub — it's been real-world validated now, not just locally built.
