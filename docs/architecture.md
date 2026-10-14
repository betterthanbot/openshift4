---
title: Architecture
parent: Platform Docs
nav_order: 2
---

# Architecture Overview

This repository manages a Single-Node OpenShift (SNO) cluster entirely via GitOps using ArgoCD / OpenShift GitOps. A single `bootstrap.yaml` applied once seeds the entire platform — from that point forward, every change is a git commit.

---

## High-Level Design

```
Git Repository (betterthanbot/openshift4)
│
└── bootstrap/bootstrap.yaml          ← Applied once manually
        │
        ▼
    ArgoCD (openshift-gitops)
        │
        ├── argocd/ (App-of-Apps)
        │     ├── AppProject
        │     ├── ApplicationSet: operators  ──► operators-nfd
        │     │                               ├── operators-gpu-operator
        │     │                               ├── operators-rhoai
        │     │                               └── … one app per operator
        │     └── ApplicationSet: workloads  ──► gatus
        │                                    ├── grafana     (dashboards)
        │                                    └── model-serving …
        │
        ├── operators/bases/<name>/                   ← Operator install + its operands
        ├── operators/overlay/my-sno-cluster/<name>/  ← Per-cluster overlay → one ArgoCD app
        └── overlay/my-sno-cluster/                   ← Per-cluster workload overlays
```

---

## App-of-Apps Pattern

The repository uses ArgoCD's **App-of-Apps** pattern:

1. `bootstrap.yaml` creates a single ArgoCD `Application` pointing at the `argocd/` directory.
2. That Application deploys the `AppProject`, and two `ApplicationSets`.
3. The ApplicationSets discover and create all remaining Applications automatically.

This means:
- Adding a new operator = create `operators/bases/<name>` and `operators/overlay/my-sno-cluster/<name>`
- Adding a new workload = create `overlay/my-sno-cluster/<name>/kustomization.yaml`
- No manual ArgoCD configuration required after bootstrap

---

## Ordering

Sync waves order the resources **inside one Application**. They do not order separate
Applications that an ApplicationSet generates, so ordering works at two levels.

**Inside an operator app** the operator's install and its operands share one sync:

| Wave | What |
|------|------|
| -3 | `Namespace` |
| -2 | `OperatorGroup` |
| -1 | `Subscription` — ArgoCD's built-in health check for OLM Subscriptions holds the sync here until the operator is installed (`status.state: AtLatestKnown`) |
| 0 and up | Operand CRs, in their own sub-waves (e.g. Grafana: datasources at 2, the token Job at 3) |

**Between apps** there is no ordering. An app that needs another app's CRDs (for example
`maas` needs `rhoai`) retries until they exist — `retry.limit: 10`, 30s→3m backoff, about 24
minutes. That is only possible because every operand carries
`SkipDryRunOnMissingResource=true`, so a missing CRD fails one resource instead of
rejecting the whole sync. The dependency table and a sync order that avoids the retries are
in `operators/README.md` (section "How a sync behaves").

Workloads (`overlay/my-sno-cluster/*`) are in the same position: they need their operators'
CRDs and rely on the same retry.

---

## Operator Bundles — `operators/`

Each operator is a Kustomize **base** plus a per-cluster **overlay**, and each overlay is one
ArgoCD Application named `operators-<name>`:

```
operators/
  bases/<name>/                     ← what to deploy (cluster-agnostic)
    namespace.yaml  operatorgroup.yaml  subscription.yaml    ← the operator, via OLM
    <operand>.yaml …                                         ← the CRs that configure it
  overlay/my-sno-cluster/<name>/    ← what this cluster changes; ArgoCD points here
```

A base bundles the two things that used to live in separate Helm charts:

- **the install** — `Namespace`, `OperatorGroup`, `Subscription`
- **the operands** — e.g. `Grafana` → a Grafana instance, `LokiStack` → a Loki cluster,
  `ClusterLogForwarder` → log collection

Because both are in one Application, the operator's CRDs are registered before its operands
are applied (see [Ordering](#ordering)), and each operator can be synced, inspected,
disabled or re-pointed on its own. Operators are switched off by listing their overlay under
`exclude:` in `argocd/appset-operators.yaml`.

Not every app is an operator: `storageclass`, `cluster-monitoring` and `maas` are platform
pieces that sit on top of operators. The full list, what each contains and what to sync first
is in `operators/README.md`.

---

## Workload Layer — `bases/` + `overlay/`

Workloads (non-operator applications) use **Kustomize overlays**:

```
bases/<name>/         ← Shared base: Helm chart or Kustomize manifests
overlay/
  my-sno-cluster/
    <name>/           ← Cluster-specific overlay
      kustomization.yaml   ← References base + applies patches
```

The `appset-workloads.yaml` ApplicationSet uses ArgoCD's **git directory generator** to auto-discover every subdirectory under `overlay/my-sno-cluster/`. Adding a new workload requires no changes to ArgoCD — just create the overlay directory.

---

## Namespace Layout

| Namespace | Contents |
|-----------|----------|
| `openshift-gitops` | ArgoCD / OpenShift GitOps |
| `grafana` | Grafana Operator + Grafana instance + dashboards + datasource |
| `openshift-logging` | Cluster Logging Operator, LokiStack, vector collector |
| `openshift-nfd` | Node Feature Discovery |
| `openshift-compliance` | Compliance Operator |
| `nvidia-gpu-operator` | NVIDIA GPU Operator |
| `stackrox` | RHACS (Central + SecuredCluster) |
| `openshift-operators` | Service Mesh 3, Connectivity Link (RHCL) and the Authorino / Limitador / DNS operators OLM pulls in with it |
| `openshift-cluster-observability-operator` | Cluster Observability Operator |
| `openshift-operators-redhat` | Loki Operator |
| `netobserv` | Network Observability operator, its LokiStack and the FlowCollector's agents |
| `openshift-cnv` | OpenShift Virtualization |
| `redhat-ods-operator` / `redhat-ods-applications` / `redhat-ods-monitoring` | RHOAI operator / its components and the MaaS metrics DB / its own monitoring stack |
| `kuadrant-system` | Kuadrant control plane (Authorino + Limitador) |
| `models-as-a-service` | MaaS tenant, subscriptions and auth policies |
| `vllm-project` | Demo models served through MaaS |
| `gatus` | Gatus uptime monitoring |
| `kyverno` | Kyverno policy engine |

---

## RBAC Model

ArgoCD's application controller SA (`openshift-gitops-argocd-application-controller`) is bound to `cluster-admin` via `argocd/rbac-operands.yaml`. This is intentional for a platform repo that manages cluster-scoped resources across all namespaces.

Grafana's `grafana-sa` ServiceAccount is bound to `cluster-monitoring-view` so it can query the in-cluster Thanos querier for metrics.

The logging collector SA (`logging-collector`) holds three ClusterRoleBindings:
- `collect-application-logs` — read pod/container logs
- `collect-infrastructure-logs` — read infra namespace logs
- `collect-audit-logs` — read audit logs from host filesystem
- `logging-collector-logs-writer` — write to LokiStack tenants

---

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| SNO (Single-Node OpenShift) | Reduces infrastructure cost for a community/lab platform |
| App-of-Apps over Helm umbrella chart | Individual apps visible in ArgoCD UI; granular sync control |
| Kustomize base + overlay for operators and workloads | One pattern for everything; per-cluster differences are small patches (a hostname, one annotation) rather than a values file |
| One app per operator, install bundled with its operands | Each operator is visible, syncable and disableable on its own, and its CRDs exist before its operands are applied (sync waves work inside one app) |
| Git directory generator for workloads | Zero-touch addition of new workloads — just create a directory |
| Sync waves inside an app, retry between apps | ArgoCD-native; no external dependency management tool. Waves do not order separate Applications, so cross-app needs rely on retry + `SkipDryRunOnMissingResource` |
| `cluster-admin` for ArgoCD SA | Platform repo manages cluster-scoped resources — scoped RBAC would require constant expansion as operators are added |
| Grafana token via Job (no static secret) | Tokens are short-lived and audience-correct; re-minted on every ArgoCD sync |
