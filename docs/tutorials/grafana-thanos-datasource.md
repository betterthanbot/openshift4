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
Grafana Pod
  │
  │  Authorization: Bearer <token>
  ▼
thanos-querier.openshift-monitoring.svc:9091
  │
  ▼
Thanos Querier (aggregates all cluster Prometheus data)
```

The bearer token comes from a Kubernetes ServiceAccount that has been granted the built-in `cluster-monitoring-view` ClusterRole. This role gives read-only access to all metrics exposed by OpenShift monitoring.

---

## What Gets Created

| Resource | Kind | Namespace | Purpose |
|---|---|---|---|
| `grafana-sa` | ServiceAccount | `grafana` | Identity for querying Thanos |
| `grafana-sa-token` | Secret (`kubernetes.io/service-account-token`) | `grafana` | Long-lived bearer token for the SA |
| `grafana-cluster-monitoring-view` | ClusterRoleBinding | cluster-scoped | Grants `grafana-sa` → `cluster-monitoring-view` |
| `thanos-prometheus` | GrafanaDatasource | `grafana` | Wires Grafana to Thanos with the token |

---

## How Token Injection Works

The Grafana Operator v5 `GrafanaDatasource` resource supports a `valuesFrom` field that performs variable substitution at reconcile time. Instead of hardcoding a token (which would rotate and break), the operator reads it from the Secret dynamically:

```yaml
spec:
  datasource:
    secureJsonData:
      httpHeaderValue1: "Bearer ${token}"   # ${token} is a placeholder
  valuesFrom:
    - valueFrom:
        secretKeyRef:
          name: grafana-sa-token
          key: token                         # matches the ${token} placeholder
```

At reconcile time, the operator substitutes `${token}` with the raw JWT from the Secret, resulting in the header `Authorization: Bearer <jwt>` being sent on every Grafana query to Thanos.

> **Note:** `targetPath` is intentionally omitted from the `valuesFrom` entry. When `targetPath` is absent, the operator treats the value as a template variable and performs `${key}` substitution inside the datasource fields. If `targetPath` were set, it would replace the entire field value — losing the `"Bearer "` prefix.

---

## Token Timing

The `grafana-sa-token` Secret is of type `kubernetes.io/service-account-token`. The `token` key inside it is **not populated immediately** — the Kubernetes API server fills it in asynchronously after the Secret is created, usually within a few seconds.

If the GrafanaDatasource reconciles before the token is ready, the Grafana Operator will log an error and retry. No manual intervention is needed; it self-heals once the token is available.

---

## Verify It's Working

### 1. Check the token Secret is populated

```bash
oc get secret grafana-sa-token -n grafana -o jsonpath='{.data.token}' | base64 -d | head -c 20
```

You should see the beginning of a JWT string (`eyJ...`).

### 2. Test the token against Thanos directly

```bash
TOKEN=$(oc get secret grafana-sa-token -n grafana -o jsonpath='{.data.token}' | base64 -d)

curl -k -H "Authorization: Bearer $TOKEN" \
  https://thanos-querier.openshift-monitoring.svc:9091/api/v1/query?query=up
```

A `200 OK` with Prometheus JSON confirms auth is working.

### 3. Check the datasource in Grafana

1. Open the Grafana route: `oc get route -n grafana`
2. Log in with the credentials configured in your `Grafana` CR
3. Navigate to **Connections → Data sources → Prometheus**
4. Click **Save & test** — you should see `Data source is working`

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `GrafanaDatasource` shows error, `${token}` not substituted | Token Secret not yet populated | Wait ~10s and re-check; the operator retries |
| `403 Forbidden` from Thanos | SA missing `cluster-monitoring-view` | Verify the `ClusterRoleBinding` exists: `oc get clusterrolebinding grafana-cluster-monitoring-view` |
| `x509: certificate signed by unknown authority` | TLS verification enabled against internal CA | Confirm `tlsSkipVerify: true` is set in `jsonData` |
| Grafana shows no data but datasource test passes | Dashboard uses a metric that doesn't exist on your cluster | Try a simple query like `up` to confirm connectivity |

---

## GitOps Integration

In this repository, all of the above resources are managed by the `operators-layer2` ArgoCD Application via the `layer2-operands` Helm chart:

- **ServiceAccount + token + ClusterRoleBinding:** `operators/layer2-operands/templates/grafana-serviceaccount.yaml`
- **GrafanaDatasource CR:** `operators/layer2-operands/templates/grafana-datasource.yaml`
- **Values (URL, names, toggles):** `operators/layer2-operands/values.yaml` under the `grafana.serviceAccount` and `grafana.datasource` keys

To disable the datasource without removing the Grafana instance, set `grafana.datasource.enabled: false` in values.yaml.

---

## Related Resources

- [Grafana Operator v5 — GrafanaDatasource CRD docs](https://github.com/grafana/grafana-operator/blob/master/docs/docs/datasources.md)
- [OpenShift Monitoring — Thanos Querier](https://docs.openshift.com/container-platform/latest/monitoring/accessing-third-party-uis.html)
- [cluster-monitoring-view ClusterRole](https://docs.openshift.com/container-platform/latest/monitoring/enabling-monitoring-for-user-defined-projects.html)
