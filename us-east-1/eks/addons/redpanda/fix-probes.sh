#!/bin/sh
# Helm postrender hook: the chart's startupProbe/livenessProbe exec commands
# are built from a template helper that appends a trailing dot to the admin
# API hostname (e.g. "redpanda-0.redpanda.redpanda.svc.cluster.local.") -
# that trailing-dot form reliably fails to resolve (curl exit 6, ~9.8s)
# even though the identical name without the dot resolves instantly. The
# chart's own postStart/preStop hook scripts build their URL without the
# trailing dot and work fine - this is an internal chart inconsistency, not
# a cluster DNS problem. No values path exists to fix the probe commands,
# so this replaces them outright with a plain curl against localhost,
# which sidesteps the bug (and DNS entirely) for a same-pod health check.
set -e

exec yq eval-all '
with(select(.kind == "StatefulSet") | .spec.template.spec.containers[] | select(.name == "redpanda");
  .startupProbe.exec.command = ["/bin/sh", "-c", "curl --silent --fail -m 5 http://localhost:9644/v1/status/ready"] |
  .startupProbe.timeoutSeconds = 5 |
  .livenessProbe.exec.command = ["/bin/sh", "-c", "curl --silent --fail -m 5 http://localhost:9644/v1/status/ready"]
)
' -
