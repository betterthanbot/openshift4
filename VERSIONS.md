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
| Grafana Community | `grafana-operator.v5.24.0` | `v5` | community-operators | `grafana` | Automatic | ✅ |
| NVIDIA GPU Operator | `gpu-operator-certified.v26.3.3` | `v26.3` | certified-operators | `nvidia-gpu-operator` | Automatic | ✅ |
| Cluster Observability | `cluster-observability-operator.v1.5.1` | `stable` | redhat-operators | `openshift-cluster-observability-operator` | Automatic | ✅ |
| Compliance Operator | `compliance-operator.v1.9.1` | `stable` | redhat-operators | `openshift-compliance` | Automatic | ✅ |
| Kernel Module Management Hub | `kernel-module-management-hub.v2.6.1` | `stable` | redhat-operators | `openshift-kmm-hub` | Automatic | ✅ |
| Cluster Logging | `cluster-logging.v6.4.6` | `stable-6.4` | redhat-operators | `openshift-logging` | Automatic | ✅ |
| Node Feature Discovery | `nfd.4.20.0-202607171900` | `stable` | redhat-operators | `openshift-nfd` | Automatic | ✅ |
| Loki Operator | `loki-operator.v6.4.6` | `stable-6.4` | redhat-operators | `openshift-operators-redhat` | Automatic | ✅ |
| Red Hat OpenShift AI | `rhods-operator.3.4.2` | `stable-3.4` | redhat-operators | `redhat-ods-operator` | Automatic | ✅ |
| RHACS | `rhacs-operator.v4.11.2` | `stable` | redhat-operators | `stackrox` | Automatic | ✅ |
| OpenShift Virtualization | `kubevirt-hyperconverged-operator.v4.20.21` | `stable` | redhat-operators | `openshift-cnv` | Automatic | ✅ |
| Network Observability | `network-observability-operator.v1.12.1` | `stable` | redhat-operators | `netobserv` | Automatic | ✅ |
| **Service Mesh 3 (Sail)** | `servicemeshoperator3.v3.4.0` | `stable` | redhat-operators | `openshift-operators` | Automatic | ✅ |
| **Connectivity Link (Kuadrant)** | `rhcl-operator.v1.4.2` | `stable` | redhat-operators | `openshift-operators` | Automatic | ✅ |
| **Kueue** | `kueue-operator.v1.3.1` | `stable-v1.3` | redhat-operators | `openshift-kueue-operator` | Automatic | ✅ |
| **Leader Worker Set** | *(latest in channel)* | `stable-v1.0` | redhat-operators | `openshift-lws-operator` | Automatic | ✅ |
| **OpenTelemetry** | `opentelemetry-operator.v0.152.0-1` | `stable` | redhat-operators | `openshift-opentelemetry-operator` | Automatic | ✅ |
| **Tempo** | `tempo-operator.v0.21.0-3` | `stable` | redhat-operators | `openshift-tempo-operator` | Automatic | ✅ |
| OpenShift GitOps | `openshift-gitops-operator.v1.21.1` | `latest` | redhat-operators | `openshift-gitops-operator` | Automatic | ❌ |
| **cert-manager** | `cert-manager-operator.v1.20.0` | `stable-v1` | redhat-operators | `cert-manager-operator` | Automatic | ❌ |
| **OpenShift Lightspeed** | `lightspeed-operator.v1.1.1` | `stable` | redhat-operators | `openshift-lightspeed` | Manual | ❌ |
| **Red Hat Quay** | `quay-operator.v3.17.3` | `stable-3.17` | redhat-operators | `openshift-operators` | Manual | ❌ |
| DevWorkspace Operator | `devworkspace-operator.v0.41.0` | `fast` | redhat-operators | `openshift-operators` | Manual | ❌ |

**Bold** rows were added in the 2026-08-04 cluster capture.

### Pulled in by OLM, deliberately not declared

Subscribing to `rhcl-operator` makes OLM resolve and install three more operators into
`openshift-operators` on its own. Declaring them here would collide with OLM's own
generated Subscriptions (named `<pkg>-<channel>-<source>-openshift-marketplace`), so
they are left alone:

| Operator | Version |
|----------|---------|
| Authorino | `1.4.2` |
| Limitador | `1.4.1` |
| Kuadrant DNS | `1.4.1` |

### Why the four disabled entries are still listed

| Operator | Why off |
|----------|---------|
| OpenShift GitOps | Must already be installed for the bootstrap Application to exist at all. |
| cert-manager | The RHPDS/OPENTLC sandbox ships it pre-installed at provisioning time, together with a `letsencrypt-production-ec2` ClusterIssuer holding sandbox-specific Route53 credentials (**not** in this repo). Enable it on a cluster that does not ship it — Kueue requires it, and the MaaS gateway consumes a cert-manager-issued Secret. |
| OpenShift Lightspeed | Installed on the source cluster but never configured — no `OLSConfig` existed. |
| Red Hat Quay | Installed on the source cluster but never configured — no `QuayRegistry` existed. |
| DevWorkspace | Not present on the cluster. |

## Actually running (verified 2026-08-04)

| Operator | Installed CSV | Phase |
|----------|--------------|-------|
| Grafana Community | `grafana-operator.v5.24.0` | Succeeded |
| NVIDIA GPU Operator | `gpu-operator-certified.v26.3.3` | Succeeded |
| Cluster Observability | `cluster-observability-operator.v1.5.1` | Succeeded |
| Compliance Operator | `compliance-operator.v1.9.1` | Succeeded |
| Kernel Module Management Hub | `kernel-module-management-hub.v2.6.1` | Succeeded |
| Cluster Logging | `cluster-logging.v6.4.6` | Succeeded |
| Node Feature Discovery | `nfd.4.20.0-202607171900` | Succeeded |
| Loki Operator | `loki-operator.v6.4.6` | Succeeded |
| Red Hat OpenShift AI | `rhods-operator.3.4.2` | Succeeded |
| RHACS | `rhacs-operator.v4.11.2` | Succeeded |
| OpenShift Virtualization | `kubevirt-hyperconverged-operator.v4.20.21` | Succeeded |
| Network Observability | `network-observability-operator.v1.12.1` | Succeeded |
| Service Mesh 3 (Sail) | `servicemeshoperator3.v3.4.0` | Succeeded |
| Connectivity Link (Kuadrant) | `rhcl-operator.v1.4.2` | Succeeded |
| Authorino | `authorino-operator.v1.4.2` | Succeeded |
| Limitador | `limitador-operator.v1.4.1` | Succeeded |
| Kuadrant DNS | `dns-operator.v1.4.1` | Succeeded |
| Kueue | `kueue-operator.v1.3.1` | Succeeded |
| Leader Worker Set | *(subscription present, no CSV installed)* | — |
| OpenTelemetry | `opentelemetry-operator.v0.152.0-1` | Succeeded |
| Tempo | `tempo-operator.v0.21.0-3` | Succeeded |
| cert-manager | `cert-manager-operator.v1.20.0` | Succeeded *(sandbox-provided)* |
| OpenShift Lightspeed | `lightspeed-operator.v1.1.1` | Succeeded *(no operand)* |
| Red Hat Quay | `quay-operator.v3.17.3` | Succeeded *(no operand)* |
| OpenShift GitOps | `openshift-gitops-operator.v1.21.1` | Succeeded *(cluster-provided)* |

As of this capture the declared floors and the running versions match — the previous
drift (including the RHOAI `stable-3.3` → `stable-3.4` minor-version gap) has been
closed by re-pinning `values.yaml` to what is live.

> RHCL **1.4.2** matters: 1.4.1 paired with Service Mesh 3.4.0 crash-looped the MaaS
> gateway. Do not downgrade it. See [techdebt.md](techdebt.md) item 5.

---

## Operand Versions

Key operands deployed by `operators/layer2-operands/`.

| Operand | Version | Notes |
|---------|---------|-------|
| LokiStack (logging) | `6.4.6` (via Loki Operator) | `1x.demo` size, AWS S3, 14-day retention |
| LokiStack (netobserv) | `6.4.6` (via Loki Operator) | `1x.pico` size, AWS S3, `openshift-network` tenant mode |
| OpenShift AI DSC/DSCI | `3.4.2` (via RHODS Operator) | API version `v2`; dashboard, aipipelines, workbenches, kserve (+ modelsAsService, NIM), llamastack, trustyai. `kueue` is **Removed** — the standalone Kueue operator owns it |
| OdhDashboardConfig | via RHOAI 3.4.2 | MaaS + Gen AI Studio feature flags; patched with ServerSideApply so the operator keeps ownership |
| RHACS Central + SecuredCluster | `4.11.2` (via RHACS Operator) | Central route enabled; needs a manual init bundle — see [README](README.md#4-configure-rhacs-post-install) |
| Grafana | `13.0.1` (via Grafana Operator) | 9 dashboards from [bases/grafana/generated/](bases/grafana/generated/); 6 datasources (Thanos, 3× Loki, RHOAI Thanos, MaaS Postgres) |
| NVIDIA ClusterPolicy | via GPU Operator `26.3.3` | Operator defaults, captured verbatim — see the long comment in [layer2 values](operators/layer2-operands/values.yaml) |
| Kuadrant | `1.4.2` (via RHCL Operator) | Creates Authorino + Limitador in `kuadrant-system`; observability on |
| Kueue | `1.3.1` (via Kueue Operator) | Cluster-scoped `Kueue/cluster`; Deployment/Pod/PyTorchJob/Ray/StatefulSet/TrainJob integrations |
| MaaS Tenant + 4 Subscriptions | via RHOAI 3.4.2 | `default-tenant` on `maas-default-gateway`; team-alpha/bravo/Charlie/Delta tiers |
| RHOAI monitoring | OTel `0.152.1`, Tempo `2.10.5` | `data-science-collector` + `data-science-tempomonolithic`, created by the DSCI, not by this chart |
| User workload monitoring | built into OCP | `enableUserWorkload: true` patched into `cluster-monitoring-config` via ServerSideApply — stands up `prometheus-user-workload` ×2 + `thanos-ruler-user-workload` ×2 |
| RHOAI monitoring workarounds | n/a | NetworkPolicy opening the Thanos gRPC sidecar port (techdebt #3) + Perses `cluster-monitoring-view` binding and CA ConfigMap (techdebt #4) |

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
