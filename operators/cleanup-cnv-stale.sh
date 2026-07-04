#!/usr/bin/env bash
# ==============================================================================
# Removes a pre-existing, orphaned OpenShift Virtualization (CNV) install.
#
# Context: this cluster had CNV installed manually at some point; its
# Subscription/CSV were later deleted without uninstalling the HyperConverged
# CR first, leaving every operand (virt-*, cdi-*, kubemacpool-*, etc.)
# orphaned with no operator reconciling it (see PLAN.md Known Issue #8).
#
# This script wipes that install entirely — including the two existing VMs
# and their disks — so operators/layer1-install + operators/layer2-operands
# can do a from-scratch install via GitOps. THERE IS NO UNDO.
#
# Deletes:
#   - VirtualMachines/VirtualMachineInstances in my-vms (fedora-copper-lemur-85,
#     rhel-9-amaranth-kangaroo-27) and their disks
#   - Namespaces: my-vms, openshift-cnv, openshift-virtualization-os-images
#   - HyperConverged/KubeVirt/CDI/NetworkAddonsConfig/SSP/MigController CRs
#   - Cluster-scoped leftovers: webhook configs, ClusterRoles/Bindings,
#     PriorityClass, ConsolePlugin, ConsoleQuickStarts, ConsoleCLIDownload
#
# Usage: ./cleanup-cnv-stale.sh [-y|--yes]
# ==============================================================================
set -euo pipefail

if [[ "${1:-}" != "-y" && "${1:-}" != "--yes" ]]; then
    cat <<'EOF'
This will PERMANENTLY DELETE:
  - VirtualMachines in my-vms (fedora-copper-lemur-85, rhel-9-amaranth-kangaroo-27) and their disks
  - Namespaces: my-vms, openshift-cnv, openshift-virtualization-os-images
  - HyperConverged/KubeVirt/CDI/NetworkAddonsConfig/SSP/MigController CRs
  - Cluster-scoped leftovers: webhook configs, ClusterRoles/Bindings, PriorityClass,
    ConsolePlugin, ConsoleQuickStarts, ConsoleCLIDownload
EOF
    read -rp "Type 'yes' to continue: " reply
    [[ "${reply}" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

echo "==> Removing dangling webhook configs first"
echo "    (stale, point at services about to be deleted — safest to clear before anything else)"
oc delete validatingwebhookconfiguration \
    cdi-api-dataimportcron-validate \
    cdi-api-datavolume-validate \
    cdi-api-populator-validate \
    cdi-api-validate \
    virt-api-validator \
    virt-operator-validator \
    virt-template-validator \
    --ignore-not-found
oc delete mutatingwebhookconfiguration \
    cdi-api-datavolume-mutate \
    cdi-api-pvc-mutate \
    kubevirt-ipam-controller-mutating-webhook-configuration \
    virt-api-mutator \
    --ignore-not-found

echo "==> Removing stale subresource APIServices (ServiceNotFound once virt-api is gone;"
echo "    left behind they break namespace-deletion API discovery CLUSTER-WIDE, not just for openshift-cnv)"
oc delete apiservice \
    v1.subresources.kubevirt.io \
    v1alpha3.subresources.kubevirt.io \
    v1beta1.upload.cdi.kubevirt.io \
    --ignore-not-found

echo "==> Deleting VirtualMachines + VirtualMachineInstances in my-vms"
echo "    (stripping kubevirt.io/virtualMachineControllerFinalize right after — don't rely on"
echo "    virt-controller surviving long enough to clear it gracefully during namespace teardown)"
oc delete vmi --all -n my-vms --ignore-not-found --wait=false || true
oc delete vm --all -n my-vms --ignore-not-found --wait=false || true
for vm in $(oc get vm -n my-vms -o name 2>/dev/null); do
    oc patch "${vm}" -n my-vms --type=merge -p '{"metadata":{"finalizers":[]}}' || true
done

NAMESPACES_TO_WATCH=()
for ns in my-vms openshift-virtualization-os-images; do
    echo "==> Deleting namespace ${ns}"
    oc delete namespace "${ns}" --ignore-not-found --wait=false
    NAMESPACES_TO_WATCH+=("${ns}")
done

echo "==> Deleting HyperConverged and dependent operand CRs in openshift-cnv"
echo "    (no operator is running to process finalizers, so we clear them right after requesting deletion)"
for res in hyperconverged/kubevirt-hyperconverged kubevirt/kubevirt-kubevirt-hyperconverged \
           ssp/ssp-kubevirt-hyperconverged migcontroller/migcontroller-kubevirt-hyperconverged; do
    kind="${res%%/*}"; name="${res##*/}"
    oc delete "${kind}" "${name}" -n openshift-cnv --ignore-not-found --wait=false || true
    oc get "${kind}" "${name}" -n openshift-cnv >/dev/null 2>&1 \
        && oc patch "${kind}" "${name}" -n openshift-cnv --type=merge -p '{"metadata":{"finalizers":[]}}' || true
done
# CDI and NetworkAddonsConfig are cluster-scoped, not namespaced
for res in cdi/cdi-kubevirt-hyperconverged networkaddonsconfig/cluster; do
    kind="${res%%/*}"; name="${res##*/}"
    oc delete "${kind}" "${name}" --ignore-not-found --wait=false || true
    oc get "${kind}" "${name}" >/dev/null 2>&1 \
        && oc patch "${kind}" "${name}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
done

echo "==> Deleting namespace openshift-cnv (cascades virt-*, cdi-*, kubemacpool-*, the OperatorGroup, etc.)"
oc delete namespace openshift-cnv --ignore-not-found --wait=false
NAMESPACES_TO_WATCH+=("openshift-cnv")

echo "==> Waiting for namespaces to finish terminating..."
for _ in $(seq 1 30); do
    still_terminating=()
    for ns in "${NAMESPACES_TO_WATCH[@]}"; do
        phase="$(oc get ns "${ns}" -o jsonpath='{.status.phase}' --request-timeout=10s 2>/dev/null || true)"
        [[ "${phase}" == "Terminating" ]] && still_terminating+=("${ns}")
    done
    [[ ${#still_terminating[@]} -eq 0 ]] && break
    sleep 5
done

# Re-sweep any CNV CRs one more time before forcing anything. The condition
# check below trusts the namespace's own NamespaceDeletionContentFailure
# status, but that field is cached and only refreshes on the controller's own
# (possibly backed-off) retry schedule — it can read "False" even when a CR
# is still sitting there with its own finalizer. Clearing here directly is
# cheap, idempotent, and closes that gap before we do anything force-y.
for res in hyperconverged/kubevirt-hyperconverged kubevirt/kubevirt-kubevirt-hyperconverged \
           ssp/ssp-kubevirt-hyperconverged migcontroller/migcontroller-kubevirt-hyperconverged; do
    kind="${res%%/*}"; name="${res##*/}"
    oc get "${kind}" "${name}" -n openshift-cnv >/dev/null 2>&1 \
        && oc patch "${kind}" "${name}" -n openshift-cnv --type=merge -p '{"metadata":{"finalizers":[]}}' || true
done

# Same safety check as bases/get-a-username/cleanup.sh: only clear a stuck
# namespace's finalizer once its own status confirms content deletion is not
# failing — never force past a namespace that still has real content stuck.
for ns in "${NAMESPACES_TO_WATCH[@]}"; do
    phase="$(oc get ns "${ns}" -o jsonpath='{.status.phase}' --request-timeout=10s 2>/dev/null || true)"
    [[ "${phase}" == "Terminating" ]] || continue

    content_removed="$(oc get ns "${ns}" -o json --request-timeout=10s \
        | jq -r '[.status.conditions[]? | select(.type == "NamespaceDeletionContentFailure")][0].status // "False"')"
    if [[ "${content_removed}" == "True" ]]; then
        echo "  ${ns}: content deletion still failing, leaving it alone — check manually (oc get ns ${ns} -o json | jq .status.conditions)"
        continue
    fi

    echo "  ${ns}: content is gone, only the finalizer is stuck — clearing it"
    oc get ns "${ns}" -o json --request-timeout=10s \
        | jq '.spec.finalizers = []' \
        | oc replace --raw "/api/v1/namespaces/${ns}/finalize" -f - >/dev/null
done

# Belt-and-suspenders: forcing a namespace's finalizer via /finalize purges
# the Namespace object immediately without waiting for children to finish
# deleting. If anything inside it still had its own finalizer at that exact
# moment, it can survive as an orphan (gettable via -A, ungettable via -n
# <ns> since the namespace itself is gone, and un-patchable because the
# NamespaceLifecycle admission plugin rejects writes scoped to a namespace
# that no longer exists). Detect that and heal it by briefly recreating the
# namespace so the patch/delete can go through, then removing it again.
echo "==> Checking for CRs orphaned by a forced namespace delete..."
orphans="$(oc get hyperconverged,kubevirt,cdi,ssp,migcontroller,networkaddonsconfig -A -o name 2>/dev/null || true)"
if [[ -n "${orphans}" ]]; then
    echo "  found orphaned CRs, healing:"
    echo "${orphans}"
    oc create namespace openshift-cnv --dry-run=client -o yaml | oc apply -f - >/dev/null 2>&1 || true
    sleep 2
    while read -r res; do
        [[ -n "${res}" ]] || continue
        oc patch "${res}" -n openshift-cnv --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || \
            oc patch "${res}" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
        oc delete "${res}" -n openshift-cnv --ignore-not-found 2>/dev/null || oc delete "${res}" --ignore-not-found || true
    done <<< "${orphans}"
    oc delete namespace openshift-cnv --ignore-not-found
fi

echo "==> Deleting cluster-scoped CNV leftovers"
oc delete priorityclass kubevirt-cluster-critical --ignore-not-found
oc delete consoleplugin kubevirt-plugin --ignore-not-found
oc delete consolequickstart creating-virtual-machine creating-virtual-machine-from-volume windows-bootsource-pipeline --ignore-not-found
oc delete consoleclidownload virtctl-clidownloads-kubevirt-hyperconverged --ignore-not-found

oc get clusterrole -o name \
    | grep -E "kubevirt|cdi\.kubevirt\.io|hco\.kubevirt\.io|hyperconverged|migrations\.kubevirt\.io|networkaddonsconfigs|aaqs\.aaq|ssps\.ssp|hostpathprovisioners|instancetype\.kubevirt\.io|os-images\.kubevirt\.io" \
    | xargs -r oc delete --ignore-not-found

oc get clusterrolebinding -o name \
    | grep -E "kubevirt|cdi" \
    | xargs -r oc delete --ignore-not-found

echo "==> Done. Verify with:"
echo "    oc get ns my-vms openshift-cnv openshift-virtualization-os-images"
echo "    oc get apiservices | grep openshift-cnv"
echo "    oc get crd | grep kubevirt"
echo ""
echo "Next: sync ArgoCD (or 'helm template'/apply operators/layer1-install + layer2-operands) for a fresh install."
