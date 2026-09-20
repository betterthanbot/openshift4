#!/usr/bin/env bash
# Workshop prep: namespace, node labels, one taint.
# Auto-discovers worker names so node replacement doesn't break the lab.
# Run once before the demo. Idempotent.
set -euo pipefail

WORKERS=()
while IFS= read -r node; do
  WORKERS+=("$node")
done < <(oc get nodes -l node-role.kubernetes.io/worker \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)

if [ "${#WORKERS[@]}" -lt 3 ]; then
  echo "ERROR: need >=3 workers, found ${#WORKERS[@]}: ${WORKERS[*]}" >&2
  exit 1
fi

WORKER_A="${WORKERS[0]}"   # "gpu" node, tainted dedicated=gpu:NoSchedule
WORKER_B="${WORKERS[1]}"   # plain worker
WORKER_C="${WORKERS[2]}"   # NoExecute victim in Demo 3

# Persist for 99-cleanup.sh and for the taint commands in the runbook.
cat > .demo-nodes <<EOF
WORKER_A=$WORKER_A
WORKER_B=$WORKER_B
WORKER_C=$WORKER_C
EOF

oc new-project sched-demo 2>/dev/null || oc project sched-demo

# --- labels -------------------------------------------------------------
oc label node "$WORKER_A" hardware=gpu node-tier=premium --overwrite
oc label node "$WORKER_B" hardware=cpu node-tier=standard --overwrite
oc label node "$WORKER_C" hardware=cpu node-tier=standard demo-role=evictme --overwrite

# --- taint --------------------------------------------------------------
# NoSchedule only. Nothing running is evicted.
oc adm taint node "$WORKER_A" dedicated=gpu:NoSchedule --overwrite

cat <<EOF

  gpu / tainted : $WORKER_A
  plain worker  : $WORKER_B
  evict victim  : $WORKER_C   (demo-role=evictme)

EOF
oc get nodes -L hardware,node-tier,demo-role
echo
oc get node "$WORKER_A" -o jsonpath='{.spec.taints}{"\n"}'
echo
echo "Zone labels (needed by d15-topologyspread):"
oc get nodes -L topology.kubernetes.io/zone --no-headers | awk '{print $1, $NF}'
