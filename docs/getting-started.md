---
title: Getting Started
parent: Platform Docs
nav_order: 1
---

# Getting Started

This guide walks you through deploying the OpenShift4 GitOps platform from scratch on a fresh cluster.

---

## Prerequisites

### Cluster

| Requirement | Details |
|-------------|---------|
| OpenShift version | 4.14 or later |
| Topology | Single-Node OpenShift (SNO) recommended; multi-node works |
| Storage | `gp3-csi` StorageClass available (AWS default) — adjust `lokiStack.spec.storageClassName` in `values.yaml` for other providers |
| AWS S3 (or compatible) | Required for LokiStack log storage — one bucket, one IAM user with read/write access |
| `cluster-admin` access | Required to apply the bootstrap Application and RBAC |

### Tooling

| Tool | Purpose |
|------|---------|
| `oc` / `kubectl` | Apply bootstrap, run verification commands |
| `git` | Clone and push changes |
| OpenShift GitOps Operator | Must be pre-installed (available from OperatorHub) |

> **OpenShift GitOps** is the only operator you install manually. Everything else is managed by this repo.

---

## Step 1 — Fork or clone the repository

```bash
git clone https://github.com/betterthanbot/openshift4.git
cd openshift4
```

If deploying to your own cluster, fork the repo and update the `repoURL` references:

```bash
# Files to update with your fork URL:
grep -r "betterthanbot/openshift4" --include="*.yaml" -l
```

---

## Step 2 — Install OpenShift GitOps

If not already installed, install the OpenShift GitOps operator from OperatorHub in the OpenShift Web Console:

1. Navigate to **OperatorHub** → search for **OpenShift GitOps**
2. Install with default settings (all namespaces, stable channel)
3. Wait for the `openshift-gitops` namespace and ArgoCD instance to appear

Verify:
```bash
oc get pods -n openshift-gitops
oc get route openshift-gitops-server -n openshift-gitops
```

---

## Step 3 — Review cluster-specific values

Before bootstrapping, review these values in `operators/layer2-operands/values.yaml` and adjust for your cluster:

| Key | Default | Notes |
|-----|---------|-------|
| `lokiStack.spec.storageClassName` | `gp3-csi` | Change for non-AWS clusters |
| `rhacs.securedCluster.clusterName` | `my-cluster` | Logical name shown in RHACS console |
| `grafana.instance.spec.config.security.admin_password` | `secret` | Change before deploying to production |

---

## Step 4 — Apply the bootstrap Application

```bash
oc apply -f bootstrap/bootstrap.yaml
```

This creates a single ArgoCD `Application` in the `openshift-gitops` namespace pointing at the `argocd/` directory. From here, ArgoCD takes over.

**What happens next (automatically):**

| Time | Event |
|------|-------|
| ~30s | ArgoCD syncs `argocd/` — creates AppProject, ApplicationSets, RBAC |
| ~2m | `operators-layer1` syncs — Namespaces, OperatorGroups, OLM Subscriptions applied |
| ~10–15m | OLM installs all operators (download + install takes time) |
| ~20m | `operators-layer2` syncs — Grafana, LokiStack, RHACS, NFD, etc. CRs applied |
| ~25m | `gatus`, `grafana`, `kyverno` workloads sync |

---

## Step 5 — Create the LokiStack S3 secret

LokiStack needs S3 credentials that are **not** stored in git. Create them manually:

```bash
oc create secret generic logging-loki-s3 \
  -n openshift-logging \
  --from-literal=access_key_id=<your-access-key-id> \
  --from-literal=access_key_secret=<your-secret-access-key> \
  --from-literal=bucketnames=<your-bucket-name> \
  --from-literal=endpoint=https://s3.ap-southeast-1.amazonaws.com \
  --from-literal=region=ap-southeast-1 \
  --dry-run=client -o yaml | oc apply -f -
```

See [lokistack-s3-setup.md](tutorials/lokistack-s3-setup.md) for full details including Web Console instructions.

---

## Step 6 — Verify the deployment

### ArgoCD UI

Open the ArgoCD route and confirm all applications are `Synced` and `Healthy`:

```bash
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'
```

Log in with your OpenShift credentials (SSO via Dex is pre-configured).

### CLI spot checks

```bash
# All ArgoCD applications
oc get applications -n openshift-gitops

# Operators installed and running
oc get csv -A | grep -v None

# Grafana instance
oc get grafana -n grafana

# LokiStack
oc get lokistack -n openshift-logging

# Log flow (should show no errors after ~5 minutes)
oc logs -n openshift-logging -l app.kubernetes.io/component=collector --tail=20

# Grafana route
oc get route -n grafana
```

---

## Accessing the platform

| Service | How to find the URL |
|---------|-------------------|
| ArgoCD | `oc get route openshift-gitops-server -n openshift-gitops` |
| Grafana | `oc get route -n grafana` |
| RHACS | `oc get route -n stackrox` |
| OpenShift AI | OpenShift Web Console → **AI/ML** section |
| Logs viewer | OpenShift Web Console → **Observe → Logs** |

---

## Resetting / Uninstalling

To delete everything managed by this repo, delete the bootstrap Application. Because cascade deletion is wired via finalizers, ArgoCD will delete all child applications and their resources:

```bash
oc delete application bootstrap -n openshift-gitops
```

> **Warning:** This deletes all operands, operator subscriptions, and workloads. It does not delete the OpenShift GitOps operator itself (which was pre-installed).
