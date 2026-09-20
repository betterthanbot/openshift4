#!/usr/bin/env bash
set -euo pipefail

if [ -f .demo-nodes ]; then
  # shellcheck disable=SC1091
  source .demo-nodes
else
  mapfile -t W < <(oc get nodes -l node-role.kubernetes.io/worker \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)
  WORKER_A="${W[0]}"; WORKER_B="${W[1]}"; WORKER_C="${W[2]}"
fi

oc delete project sched-demo --ignore-not-found

# taints off (trailing "-" removes)
oc adm taint node "$WORKER_A" dedicated:NoSchedule-   || true
oc adm taint node "$WORKER_C" maintenance:NoExecute-  || true

# labels off
for n in "$WORKER_A" "$WORKER_B" "$WORKER_C"; do
  oc label node "$n" hardware-   --overwrite || true
  oc label node "$n" node-tier-  --overwrite || true
  oc label node "$n" demo-role-  --overwrite || true
  oc uncordon "$n" || true
done

rm -f .demo-nodes
oc get nodes -L hardware,node-tier,demo-role
