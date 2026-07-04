#!/bin/bash
set -euo pipefail

# Tears down everything init.sh created for a workshop run: per-user
# namespaces (and everything a user deployed inside them — deleting the
# namespace deletes its contents), User/Identity objects, the workshop
# HTPasswd identity provider, and its Secret.
#
# Usage:
#   ./cleanup.sh          # interactive confirmation
#   ./cleanup.sh -y        # skip confirmation (e.g. CI)

USER_PREFIX="user"
USER_COUNT=10

HTPASSWD_SECRET_NAME="workshop-htpasswd"
HTPASSWD_SECRET_NAMESPACE="openshift-config"
HTPASSWD_IDP_NAME="workshop-htpasswd"

# Legacy namespace suffixes from earlier versions of init.sh (label-ns.sh),
# in case this cleans up a run from before the naming was simplified.
LEGACY_SUFFIXES=("" "-dev" "-sit")

ASSUME_YES=false
if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
    ASSUME_YES=true
fi

echo "This will permanently delete:"
echo "  - Namespaces ${USER_PREFIX}1..${USER_PREFIX}${USER_COUNT} (and any -dev/-sit variants),"
echo "    including everything users deployed inside them"
echo "  - User objects ${USER_PREFIX}1..${USER_PREFIX}${USER_COUNT} and their Identities"
echo "  - The ${HTPASSWD_IDP_NAME} identity provider entry on oauth/cluster"
echo "    (other identity providers, if any, are left untouched)"
echo "  - The ${HTPASSWD_SECRET_NAME} secret in ${HTPASSWD_SECRET_NAMESPACE}"
echo
echo "This does NOT remove the get-a-username tool itself (that's managed by ArgoCD;"
echo "remove overlay/my-sno-cluster/get-a-username/ from git if you want it gone too)."
echo

if [[ "${ASSUME_YES}" != "true" ]]; then
    read -r -p "Continue? [y/N] " confirm
    if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

NAMESPACES_TO_WATCH=()

for i in $(seq 1 "${USER_COUNT}"); do
    USER_NAME="${USER_PREFIX}${i}"

    for suffix in "${LEGACY_SUFFIXES[@]}"; do
        ns="${USER_PREFIX}${i}${suffix}"
        if oc get ns "${ns}" &>/dev/null; then
            echo "Deleting namespace ${ns} (and everything in it)..."
            # --wait=false: don't block here. If cluster-side namespace
            # controller can't finish (e.g. stale API discovery from another
            # operator), `oc delete ns` hangs forever waiting for a
            # termination that will never complete on its own. Request
            # deletion and move on; force_stuck_namespaces below cleans up
            # anything still stuck once every delete has been requested.
            oc delete ns "${ns}" --ignore-not-found --wait=false
            NAMESPACES_TO_WATCH+=("${ns}")
        fi
    done

    # Identities are not garbage-collected when the User is deleted — remove
    # any that reference this user first, then the User itself.
    oc get identity -o json \
        | jq -r --arg u "${USER_NAME}" '.items[] | select(.user.name == $u) | .metadata.name' \
        | while read -r identity; do
            [[ -n "${identity}" ]] || continue
            echo "Deleting identity ${identity}..."
            oc delete identity "${identity}" --ignore-not-found
        done

    echo "Deleting user ${USER_NAME}..."
    oc delete user "${USER_NAME}" --ignore-not-found

    echo "Done cleaning up ${USER_NAME}."
done

# Force-clear namespaces still stuck in Terminating after their content is
# already gone (typically NamespaceDeletionDiscoveryFailure — a stale/broken
# APIService elsewhere on the cluster, e.g. KubeVirt, blocks the namespace
# controller from ever finishing its discovery check). Safe here because we
# only touch namespaces whose own status says content is already removed.
force_stuck_namespaces() {
    echo "Checking for namespaces still stuck in Terminating..."
    local ns phase content_removed
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
}
force_stuck_namespaces

echo "Removing ${HTPASSWD_IDP_NAME} from oauth/cluster identity providers..."
remaining_providers="$(oc get oauth cluster -o json \
    | jq --arg name "${HTPASSWD_IDP_NAME}" '(.spec.identityProviders // []) | map(select(.name != $name))')"
oc patch oauth cluster --type=merge -p "$(jq -n --argjson providers "${remaining_providers}" '{spec: {identityProviders: $providers}}')"

echo "Deleting ${HTPASSWD_SECRET_NAME} secret in ${HTPASSWD_SECRET_NAMESPACE}..."
oc delete secret "${HTPASSWD_SECRET_NAME}" -n "${HTPASSWD_SECRET_NAMESPACE}" --ignore-not-found

echo "Cleanup complete."
