# Operator Versions

Pinned versions for all operators managed by `operators/layer1-install/`.
Update `startingCSV` and `channel` in `operators/layer1-install/values.yaml` when upgrading.

| Operator | CSV / Version | Channel | Source | Namespace | Approval | Enabled |
|----------|--------------|---------|--------|-----------|----------|---------|
| Grafana Community | `grafana-operator.v5.22.2` | `v5` | community-operators | `grafana` | Automatic | ✅ |
| NVIDIA GPU Operator | `gpu-operator-certified.v26.3.2` | `v26.3` | certified-operators | `nvidia-gpu-operator` | Automatic | ✅ |
| Cluster Observability | `cluster-observability-operator.v1.4.0` | `stable` | redhat-operators | `openshift-cluster-observability-operator` | Automatic | ✅ |
| Compliance Operator | `compliance-operator.v1.8.2` | `stable` | redhat-operators | `openshift-compliance` | Automatic | ✅ |
| Kernel Module Management Hub | `kernel-module-management-hub.v2.6.0` | `stable` | redhat-operators | `openshift-kmm-hub` | Automatic | ✅ |
| Cluster Logging | `cluster-logging.v6.4.3` | `stable-6.4` | redhat-operators | `openshift-logging` | Automatic | ✅ |
| Node Feature Discovery | `nfd.4.20.0-202603051149` | `stable` | redhat-operators | `openshift-nfd` | Automatic | ✅ |
| Loki Operator | `loki-operator.v6.4.3` | `stable-6.4` | redhat-operators | `openshift-operators-redhat` | Automatic | ✅ |
| DevWorkspace Operator | `devworkspace-operator.v0.41.0` | `fast` | redhat-operators | `openshift-operators` | Manual | ✅ |
| Red Hat OpenShift AI | `rhods-operator.3.4.1` | `stable-3.4` | redhat-operators | `redhat-ods-operator` | Automatic | ✅ |
| RHACS | `rhacs-operator.v4.11.0` | `stable` | redhat-operators | `stackrox` | Automatic | ✅ |
| OpenShift GitOps | `openshift-gitops-operator.v1.20.4` | `latest` | redhat-operators | `openshift-gitops-operator` | Automatic | ❌ |
| Network Observability | `netobserv-operator` (latest) | `stable` | redhat-operators | `netobserv` | Automatic | ✅ |

---

## Operand Versions

Key operand images and versions deployed by `operators/layer2-operands/`.

| Operand | Version | Notes |
|---------|---------|-------|
| LokiStack (logging) | `6.4.3` (via Loki Operator) | `1x.pico` size, AWS S3, 14-day retention |
| LokiStack (netobserv) | `6.4.3` (via Loki Operator) | `1x.pico` size, AWS S3, `openshift-network` tenant mode |
| OpenShift AI DSC/DSCI | `3.4.1` (via RHODS Operator) | API version `v2`; components: dashboard, aipipelines, workbenches |
| RHACS Central + SecuredCluster | `4.11.0` (via RHACS Operator) | Central route enabled |

---

## How to upgrade an operator

1. Find the new CSV name:
   ```bash
   oc get packagemanifest <package-name> -n openshift-marketplace \
     -o jsonpath='{.status.channels[?(@.name=="<channel>")].currentCSV}'
   ```
2. Update `startingCSV` (and `channel` if changing) in `operators/layer1-install/values.yaml`.
3. If `installPlanApproval: Manual`, approve the InstallPlan after sync:
   ```bash
   oc get installplan -n <namespace>
   oc patch installplan <name> -n <namespace> \
     --type merge -p '{"spec":{"approved":true}}'
   ```
