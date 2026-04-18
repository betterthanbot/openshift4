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
        │     ├── ApplicationSet: operators  ──► operators-layer1 (wave 1)
        │     │                               └► operators-layer2 (wave 2)
        │     └── ApplicationSet: workloads  ──► gatus    (wave 3)
        │                                    ├── grafana  (wave 3)
        │                                    └── kyverno  (wave 3)
        │
        ├── operators/layer1-install/         ← OLM Subscriptions + Namespaces
        ├── operators/layer2-operands/        ← Operator CRs / Operands
        └── overlay/my-sno-cluster/           ← Per-cluster workload overlays
```

---

## App-of-Apps Pattern

The repository uses ArgoCD's **App-of-Apps** pattern:

1. `bootstrap.yaml` creates a single ArgoCD `Application` pointing at the `argocd/` directory.
2. That Application deploys the `AppProject`, and two `ApplicationSets`.
3. The ApplicationSets discover and create all remaining Applications automatically.

This means:
- Adding a new operator = edit `operators/layer1-install/values.yaml`
- Adding a new workload = create `overlay/my-sno-cluster/<name>/kustomization.yaml`
- No manual ArgoCD configuration required after bootstrap

---

## Sync Wave Ordering

Sync waves ensure resources are applied in dependency order:

| Wave | ArgoCD App | What it deploys | Waits for |
|------|-----------|-----------------|-----------|
| 0 | bootstrap | `argocd/` — AppProject, ApplicationSets, RBAC | Nothing |
| 1 | operators-layer1 | Namespaces, OperatorGroups, OLM Subscriptions | Wave 0 |
| 2 | operators-layer2 | Operator CRs (Grafana, LokiStack, RHACS, etc.) | Wave 1 (operators Ready) |
| 3 | gatus, grafana, kyverno | Workload deployments and dashboard CRs | Wave 2 |

Within `operators-layer2`, sub-waves further order dependencies:
- Wave 1: Grafana auth Job (mints the Thanos bearer token)
- Wave 2: GrafanaDatasource (reads token written by the Job)

---

## Two-Layer Operator Model

### Layer 1 — `operators/layer1-install/`

A Helm chart that installs operators via OLM. For each operator it creates:
- `Namespace` — dedicated namespace for the operator
- `OperatorGroup` — scopes which namespaces the operator watches
- `Subscription` — tells OLM which channel/version to install

Operators are toggled with `enabled: true/false` in `operators/layer1-install/values.yaml`.

### Layer 2 — `operators/layer2-operands/`

A Helm chart that creates the operator **Custom Resources** (operands) once operators are running. Examples:
- `Grafana` CR → tells the Grafana Operator to create a Grafana instance
- `LokiStack` CR → tells the Loki Operator to deploy a Loki cluster
- `ClusterLogForwarder` CR → tells the Logging Operator to collect and forward logs

Operands are toggled with `enabled: true/false` per-section in `operators/layer2-operands/values.yaml`.

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
| `openshift-kmm-hub` | Kernel Module Management |
| `nvidia-gpu-operator` | NVIDIA GPU Operator |
| `stackrox` | RHACS (Central + SecuredCluster) |
| `redhat-ods-operator` | OpenShift AI / RHODS |
| `openshift-operators` | DevWorkspace, Cluster Observability |
| `openshift-operators-redhat` | Loki Operator |
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
| Helm for operators, Kustomize for workloads | Operators need templated values; workloads need overlay-per-cluster |
| Git directory generator for workloads | Zero-touch addition of new workloads — just create a directory |
| Sync waves over dependencies | ArgoCD-native; no external dependency management tool needed |
| `cluster-admin` for ArgoCD SA | Platform repo manages cluster-scoped resources — scoped RBAC would require constant expansion as operators are added |
| Grafana token via Job (no static secret) | Tokens are short-lived and audience-correct; re-minted on every ArgoCD sync |
