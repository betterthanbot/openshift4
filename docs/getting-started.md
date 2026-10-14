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
| Storage | `gp3-csi` StorageClass available (AWS default) — adjust `storageClassName` in `operators/bases/cluster-logging/lokistack.yaml` and `operators/bases/netobserv/lokistack.yaml` for other providers |
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

Each operator is its own base under `operators/bases/<name>/`, with a per-cluster overlay under
`operators/overlay/my-sno-cluster/<name>/`. Before bootstrapping, review these and adjust for your cluster
(`grep -rn "CHANGE ME" operators/` lists the ones marked in the files):

| File | Setting | Default | Notes |
|------|---------|---------|-------|
| `operators/bases/{cluster-logging,netobserv}/lokistack.yaml` | `storageClassName` | `gp3-csi` | Change for non-AWS clusters |
| `operators/overlay/my-sno-cluster/maas/kustomization.yaml` | gateway `hostname` | this sandbox's domain | Must be `maas.apps.<your-cluster-domain>` |
| `operators/bases/rhacs/securedcluster.yaml` | `clusterName` | `my-cluster` | Logical name shown in RHACS console |
| `operators/bases/grafana-operator/grafana.yaml` | `admin_password` | `secret` | Change before deploying to production |
| `operators/overlay/my-sno-cluster/cnv/kustomization.yaml` | software emulation | on | Delete the patch on bare-metal nodes |

---

## Step 4 — Apply the bootstrap Application

```bash
oc apply -f bootstrap/bootstrap.yaml
```

This creates a single ArgoCD `Application` in the `openshift-gitops` namespace pointing at the `argocd/` directory. From here, ArgoCD takes over.

**What happens next (automatically):**

| Time | Event |
|------|-------|
| ~30s | ArgoCD syncs `argocd/` — creates the AppProject, ApplicationSets and RBAC. The ApplicationSets then generate one Application per operator (`operators-*`) and one per workload |
| you | Nothing is automated — sync the `operators-*` apps in the UI, or all at once: `argocd app sync -l app.kubernetes.io/part-of=openshift4-operators` |
| ~10–15m | Each operator app installs its operator (Namespace → OperatorGroup → Subscription), waits for OLM, then applies its operands. Apps that need another app's CRDs (e.g. `maas` needs `rhoai`) retry until they exist |
| after | Workloads (`gatus`, `grafana`, `model-serving`, …) sync — they also retry until their operators' CRDs exist |

The order that avoids the retries is in `operators/README.md` (section "How a sync behaves").

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

Then re-sync `operators-cluster-logging`. See [lokistack-s3-setup.md](tutorials/lokistack-s3-setup.md) for full details including Web Console instructions.

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

Deleting the bootstrap Application deletes the ApplicationSets it created, and with them the workload Applications and their resources. It deliberately does **not** remove the operators: the operators ApplicationSet sets `preserveResourcesOnDeletion: true`, so LokiStack, the DataScienceCluster and their volumes survive an accidental delete.

To tear the whole platform down, remove the operator apps with cascade first, then bootstrap:

```bash
argocd app delete -l app.kubernetes.io/part-of=openshift4-operators --cascade
oc delete application bootstrap -n openshift-gitops
```

> **Warning:** This deletes all operands, operator subscriptions, and workloads. It does not delete the OpenShift GitOps operator itself (which was pre-installed). Deleting a Subscription also leaves its ClusterServiceVersion behind — see `docs/tutorials/operator-management.md`.
