---
title: Grafana + Thanos Datasource
parent: Tutorials
nav_order: 3
---

# Grafana + Thanos Datasource on OpenShift

**Audience:** Platform / SRE engineers setting up community Grafana on OpenShift
**Operators required:** [Grafana Operator v5 (community)](https://operatorhub.io/operator/grafana-operator)

---

## Overview

OpenShift ships with a built-in Prometheus + Thanos stack in the `openshift-monitoring` namespace. By default, only the built-in OpenShift console can query it. This tutorial wires a self-managed Grafana instance (via the community Grafana Operator v5) to that same Thanos querier so you can build custom dashboards over your cluster metrics.

The same bearer token mechanism also covers the three Loki datasources (application, infrastructure, audit), since LokiStack uses the same ServiceAccount and token approach.

---

## Key Concept: Use the Internal Service URL

Your Thanos querier is exposed externally at a URL like:

```
https://thanos-querier-openshift-monitoring.apps.<cluster-domain>/api
```

**Do not use this URL in your datasource.** It changes per cluster and breaks portability.

Instead, use the **in-cluster Kubernetes service DNS name**:

```
https://thanos-querier.openshift-monitoring.svc:9091
```

This address is identical on every OpenShift cluster. A Grafana datasource configured with this URL will work without modification when deployed to a different cluster.

---

## Architecture

```
ArgoCD sync (wave 3)
  └─ grafana-auth-job
       │  oc create token grafana-sa --duration=7440h
       │
       ├─ oc patch GrafanaDatasource/thanos-prometheus
       ├─ oc patch GrafanaDatasource/loki-application
       ├─ oc patch GrafanaDatasource/loki-infrastructure
       └─ oc patch GrafanaDatasource/loki-audit
              │
              │  (Grafana Operator reconciles each CR)
              ▼
         Grafana API ← secureJsonData.httpHeaderValue1 = "Bearer <token>"
              │
              │  Authorization: Bearer <token>
              ▼
    thanos-querier.openshift-monitoring.svc:9091
    logging-loki-gateway-http.openshift-logging.svc:8080
```

The bearer token comes from `oc create token grafana-sa --duration=7440h`. The `grafana-sa` ServiceAccount holds the `cluster-monitoring-view` ClusterRoleBinding (for Thanos) and `cluster-admin` ClusterRoleBinding (required for LokiStack OPA gateway audit log access).

---

## What Gets Created

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `grafana-sa` | ServiceAccount | `grafana` | Identity for querying Thanos and LokiStack |
| `grafana-cluster-monitoring-view` | ClusterRoleBinding | cluster-scoped | Grants `grafana-sa` read access to all cluster metrics |
| `grafana-sa-cluster-admin` | ClusterRoleBinding | cluster-scoped | Required for LokiStack OPA gateway audit log access |
| `grafana-token-builder-sa` | ServiceAccount | `grafana` | Identity for the sync-hook Job |
| `grafana-token-builder` | Role + RoleBinding | `grafana` | Allows Job to create tokens, write Secret, patch GrafanaDatasources |
| `grafana-create-thanos-auth` | Job (Sync hook, wave 3) | `grafana` | Creates token and patches all GrafanaDatasource CRs |
| `grafana-thanos-auth` | Secret | `grafana` | Written by the Job for reference/debugging; contains `bearer-token` |
| `thanos-prometheus` | GrafanaDatasource | `grafana` | Wires Grafana to Thanos |
| `loki-application` | GrafanaDatasource | `grafana` | Loki application tenant |
| `loki-infrastructure` | GrafanaDatasource | `grafana` | Loki infrastructure tenant |
| `loki-audit` | GrafanaDatasource | `grafana` | Loki audit tenant |

---

## How Token Injection Works

The Grafana Operator v5 `valuesFrom` field was evaluated and found unreliable for `secureJsonData` injection — the operator sends the empty spec value to Grafana, overwriting any previously stored token. Instead, the sync-hook Job patches each `GrafanaDatasource` CR directly:

```bash
TOKEN=$(oc create token grafana-sa -n grafana --duration=7440h)

for CR in $(oc get grafanadatasource -n grafana -o name); do
  oc patch "${CR}" -n grafana \
    --type merge \
    -p "{\"spec\":{\"datasource\":{\"secureJsonData\":{\"httpHeaderValue1\":\"Bearer ${TOKEN}\"}}}}"
done
```

Patching the CR triggers the Grafana Operator to reconcile immediately. On reconciliation, the operator reads `spec.datasource.secureJsonData.httpHeaderValue1` and calls the Grafana API to update the datasource with the token. Grafana then sends `Authorization: Bearer <token>` on every query.

### Why wave 3?

The Job runs at sync-wave `"3"`. The `GrafanaDatasource` CRs are applied by ArgoCD at wave `"2"`. Running the Job at wave 3 ensures the CRs exist before the patch is attempted, and that the patch is not overwritten by ArgoCD's wave-2 apply.

### Why ArgoCD ignoreDifferences?

`secureJsonData` is omitted from the git spec intentionally. Without `ignoreDifferences`, ArgoCD would detect the Job's patch as drift and reset the field to absent on the next sync. The following entry in `argocd/appset-operators.yaml` prevents this:

```yaml
ignoreDifferences:
  - group: grafana.integreatly.org
    kind: GrafanaDatasource
    jsonPointers:
      - /spec/datasource/secureJsonData
```

Combined with `RespectIgnoreDifferences=true` in syncOptions, ArgoCD does not include `secureJsonData` in its Server-Side Apply payload, so the field persists between syncs.

---

## Verify It's Working

### 1. Check the Job completed successfully

```bash
oc logs -n grafana -l job-name=grafana-create-thanos-auth --tail=20
```

You should see lines like:
```
patched grafanadatasource.grafana.integreatly.org/thanos-prometheus
patched grafanadatasource.grafana.integreatly.org/loki-application
...
Done: all GrafanaDatasource CRs patched with fresh bearer token
```

### 2. Verify secureJsonData is set on the CR

```bash
oc get grafanadatasource thanos-prometheus -n grafana \
  -o jsonpath='{.spec.datasource.secureJsonData}'
```

You should see `{"httpHeaderValue1":"Bearer eyJ..."}`.

### 3. Test the token against Thanos directly

```bash
TOKEN=$(oc get secret grafana-thanos-auth -n grafana \
  -o jsonpath='{.data.bearer-token}' | base64 -d | sed 's/Bearer //')

curl -k -H "Authorization: Bearer $TOKEN" \
  https://thanos-querier.openshift-monitoring.svc:9091/api/v1/query?query=up
```

A `200 OK` with Prometheus JSON confirms the token is valid.

### 4. Check the datasource in Grafana

1. Open the Grafana route: `oc get route -n grafana`
2. Log in with the credentials configured in your `Grafana` CR
3. Navigate to **Connections → Data sources → Prometheus**
4. Click **Save & test** — you should see `Data source is working`

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| Job fails: `cannot create token` | `grafana-token-builder-sa` missing `serviceaccounts/token` permission | Check the `grafana-token-builder` Role in `grafana-serviceaccount.yaml` |
| Job fails: `secrets ... is forbidden` | Role missing `get`/`create`/`patch` on `secrets` | Check the `grafana-token-builder` Role |
| `secureJsonData` absent after sync | Job ran at wave 1 (before datasource CRs existed) | Ensure job sync-wave is `"3"` |
| `secureJsonData` cleared after next sync | `ignoreDifferences` missing or `RespectIgnoreDifferences=true` not set | Check `argocd/appset-operators.yaml` |
| `401 Unauthorized` from Thanos | SA missing `cluster-monitoring-view` | Verify: `oc get clusterrolebinding grafana-cluster-monitoring-view` |
| `401 Unauthorized` from LokiStack | SA missing `cluster-admin` | Verify: `oc get clusterrolebinding grafana-sa-cluster-admin` |
| `x509: certificate signed by unknown authority` | TLS verification enabled against internal CA | Confirm `tlsSkipVerify: true` is set in `jsonData` |
| Loki datasource health check fails | Known cosmetic issue — Grafana Loki plugin sends PromQL as health check; LokiStack returns HTML for invalid LogQL | Ignore the health check; use standard Explore view to verify queries work |

---

## GitOps Integration

All resources are managed by the `operators-layer2` ArgoCD Application via the `layer2-operands` Helm chart:

- **ServiceAccount + RBAC:** `operators/layer2-operands/templates/grafana-serviceaccount.yaml`
- **Auth Job:** `operators/layer2-operands/templates/grafana-auth-job.yaml`
- **Prometheus GrafanaDatasource:** `operators/layer2-operands/templates/grafana-datasource.yaml`
- **Loki GrafanaDatasources:** `operators/layer2-operands/templates/grafana-loki-datasources.yaml`
- **ArgoCD ignoreDifferences:** `argocd/appset-operators.yaml` under `ignoreDifferences`
- **Values (URLs, names, toggles):** `operators/layer2-operands/values.yaml` under `grafana.serviceAccount`, `grafana.datasource`, and `grafana.lokiDatasources`

To disable the datasource without removing the Grafana instance, set `grafana.datasource.enabled: false` in values.yaml.

---

## Related Resources

- [Grafana Operator v5 — GrafanaDatasource CRD docs](https://github.com/grafana/grafana-operator/blob/master/docs/docs/datasources.md)
- [OpenShift Monitoring — Thanos Querier](https://docs.openshift.com/container-platform/latest/monitoring/accessing-third-party-uis.html)
- [cluster-monitoring-view ClusterRole](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
