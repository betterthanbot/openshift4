# Operator Versions

Version floors for all operators managed by `operators/layer1-install/`.

> **`startingCSV` is a floor, not a pin.** Every subscription here uses
> `installPlanApproval: Automatic`, so OLM installs *at least* the named CSV and then
> upgrades freely to the head of the channel. If you need an actual pin, switch that
> operator to `installPlanApproval: Manual` — editing `startingCSV` alone will not hold
> a version. The drift this produces is tracked as item 10 in [techdebt.md](techdebt.md).

## Declared in `values.yaml`

| Operator | `startingCSV` | Channel | Source | Namespace | Approval | Enabled |
|----------|--------------|---------|--------|-----------|----------|---------|
| Grafana Community | `grafana-operator.v5.22.2` | `v5` | community-operators | `grafana` | Automatic | ✅ |
| NVIDIA GPU Operator | `gpu-operator-certified.v26.3.2` | `v26.3` | certified-operators | `nvidia-gpu-operator` | Automatic | ✅ |
| Cluster Observability | `cluster-observability-operator.v1.4.0` | `stable` | redhat-operators | `openshift-cluster-observability-operator` | Automatic | ✅ |
| Compliance Operator | `compliance-operator.v1.8.2` | `stable` | redhat-operators | `openshift-compliance` | Automatic | ✅ |
| Kernel Module Management Hub | `kernel-module-management-hub.v2.6.0` | `stable` | redhat-operators | `openshift-kmm-hub` | Automatic | ✅ |
| Cluster Logging | `cluster-logging.v6.4.3` | `stable-6.4` | redhat-operators | `openshift-logging` | Automatic | ✅ |
| Node Feature Discovery | `nfd.4.20.0-202603051149` | `stable` | redhat-operators | `openshift-nfd` | Automatic | ✅ |
| Loki Operator | `loki-operator.v6.4.3` | `stable-6.4` | redhat-operators | `openshift-operators-redhat` | Automatic | ✅ |
| Red Hat OpenShift AI | `rhods-operator.3.3.2` | `stable-3.3` | redhat-operators | `redhat-ods-operator` | Automatic | ✅ |
| RHACS | `rhacs-operator.v4.10.0` | `stable` | redhat-operators | `stackrox` | Automatic | ✅ |
| OpenShift Virtualization | `kubevirt-hyperconverged-operator.v4.20.15` | `stable` | redhat-operators | `openshift-cnv` | Automatic | ✅ |
| Network Observability | *(latest in channel)* | `stable` | redhat-operators | `netobserv` | Automatic | ✅ |
| OpenShift GitOps | `openshift-gitops-operator.v1.20.4` | `latest` | redhat-operators | `openshift-gitops-operator` | Automatic | ❌ |
| DevWorkspace Operator | `devworkspace-operator.v0.41.0` | `fast` | redhat-operators | `openshift-operators` | Manual | ❌ |

**OpenShift GitOps** is disabled because it must already be installed for the bootstrap
Application to exist at all — leave it off unless you are managing the operator itself
from here. **DevWorkspace** is disabled and is not present on the cluster.

## Actually running (verified 2026-07-26)

| Operator | Installed CSV | Phase |
|----------|--------------|-------|
| Grafana Community | `grafana-operator.v5.24.0` | Succeeded |
| NVIDIA GPU Operator | `gpu-operator-certified.v26.3.3` | Succeeded |
| Cluster Observability | `cluster-observability-operator.v1.5.1` | Succeeded |
| Compliance Operator | `compliance-operator.v1.9.1` | Succeeded |
| Kernel Module Management Hub | `kernel-module-management-hub.v2.6.1` | **Installing** |
| Cluster Logging | `cluster-logging.v6.4.6` | Succeeded |
| Node Feature Discovery | `nfd.4.20.0-202607141145` | Succeeded |
| Loki Operator | `loki-operator.v6.4.6` | Succeeded |
| Red Hat OpenShift AI | `rhods-operator.3.4.2` | Succeeded |
| RHACS | `rhacs-operator.v4.11.1` | Succeeded |
| OpenShift Virtualization | `kubevirt-hyperconverged-operator.v4.20.21` | Succeeded |
| Network Observability | `network-observability-operator.v1.12.1` | Succeeded |
| OpenShift GitOps | `openshift-gitops-operator.v1.21.1` | Succeeded *(cluster-provided)* |

RHOAI is the only entry whose **channel** differs (`stable-3.3` declared, `stable-3.4`
running), so it is drift across a minor version rather than within a channel.

## Present on the cluster, not managed by this repo

These arrive with the RHOAI / MaaS stack and the sandbox base image. Nothing here
installs or upgrades them, but two known issues turn on their versions
([techdebt.md](techdebt.md) items 5 and 7), so they are worth recording:

| Operator | Version |
|----------|---------|
| Red Hat Connectivity Link (RHCL / Kuadrant) | `1.4.2` |
| Red Hat OpenShift Service Mesh 3 | `3.4.0` |
| Authorino | `1.4.2` |
| Limitador | `1.4.1` |
| Red Hat build of Kueue | `1.3.1` |
| Red Hat build of OpenTelemetry | `0.152.0-1` |
| Tempo | `0.21.0-3` |
| cert-manager for OpenShift | `1.20.0` |
| Red Hat Quay | `3.17.3` |
| Leader Worker Set | `1.0.0` |

> RHCL **1.4.2** matters: 1.4.1 paired with Service Mesh 3.4.0 crash-looped the MaaS
> gateway. Do not downgrade it. See [techdebt.md](techdebt.md) item 5.

---

## Operand Versions

Key operands deployed by `operators/layer2-operands/`.

| Operand | Version | Notes |
|---------|---------|-------|
| LokiStack (logging) | `6.4.6` (via Loki Operator) | `1x.pico` size, AWS S3, 14-day retention |
| LokiStack (netobserv) | `6.4.6` (via Loki Operator) | `1x.pico` size, AWS S3, `openshift-network` tenant mode |
| OpenShift AI DSC/DSCI | `3.4.2` (via RHODS Operator) | API version `v2`; components: dashboard, aipipelines, workbenches |
| RHACS Central + SecuredCluster | `4.11.1` (via RHACS Operator) | Central route enabled; needs a manual init bundle — see [README](README.md#4-configure-rhacs-post-install) |
| Grafana | `13.0.1` (via Grafana Operator) | 9 dashboards from [bases/grafana/generated/](bases/grafana/generated/) |

---

## How to check what is actually installed

```bash
oc get csv -A -o json | jq -r '[.items[] | {n:.metadata.name, v:.spec.version, p:.status.phase}]
  | unique_by(.n) | .[] | [.n, .v, .p] | @tsv' | column -t
```

CSVs are copied into every namespace by the global OperatorGroups, hence the
`unique_by`.

## How to upgrade an operator

1. Find the new CSV name:
   ```bash
   oc get packagemanifest <package-name> -n openshift-marketplace \
     -o jsonpath='{.status.channels[?(@.name=="<channel>")].currentCSV}'
   ```
2. Update `startingCSV` (and `channel` if changing) in `operators/layer1-install/values.yaml`.
   With `Automatic` approval this only raises the floor for a fresh install — an existing
   cluster has already moved on its own.
3. If `installPlanApproval: Manual`, approve the InstallPlan after sync:
   ```bash
   oc get installplan -n <namespace>
   oc patch installplan <name> -n <namespace> \
     --type merge -p '{"spec":{"approved":true}}'
   ```
4. Update the "Actually running" table above so the two stay comparable.
