---
title: Adding a Workload
parent: Tutorials
nav_order: 2
---

# Adding a New Workload

Workloads (non-operator applications like Gatus, Grafana dashboards, and Kyverno) use a **base + overlay** pattern. ArgoCD automatically discovers and deploys any new overlay directory — no changes to ArgoCD configuration are needed.

---

## How it works

```
bases/<name>/               ← Shared base (Helm chart or plain Kustomize manifests)
overlay/
  my-sno-cluster/
    <name>/                 ← Your new workload directory
      kustomization.yaml    ← References the base; ArgoCD auto-discovers this
      namespace.yaml        ← Optional: creates the namespace if it doesn't exist
      <patches>.yaml        ← Optional: cluster-specific overrides
```

The `appset-workloads.yaml` ApplicationSet scans `overlay/my-sno-cluster/*` for directories containing a `kustomization.yaml`. Each directory becomes one ArgoCD Application, named after the directory.

---

## Option A — Kustomize overlay (recommended for simple workloads)

### Step 1 — Create the base (if it doesn't exist)

```
bases/my-app/
  kustomization.yaml
  deployment.yaml
  service.yaml
  route.yaml
```

`bases/my-app/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: my-app

resources:
  - deployment.yaml
  - service.yaml
  - route.yaml
```

### Step 2 — Create the cluster overlay

```
overlay/my-sno-cluster/my-app/
  kustomization.yaml
  namespace.yaml
```

`overlay/my-sno-cluster/my-app/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../bases/my-app/
  - namespace.yaml
```

`overlay/my-sno-cluster/my-app/namespace.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
```

### Step 3 — Commit and push

```bash
git add overlay/my-sno-cluster/my-app/
git commit -m "add my-app workload overlay"
git push
```

ArgoCD detects the new directory within ~3 minutes (or immediately if webhooks are configured) and creates a new Application named `my-app`.

---

## Option B — Helm chart base

If your workload is better represented as a Helm chart:

```
bases/my-app/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
```

The overlay can then provide cluster-specific `values.yaml` overrides:

`overlay/my-sno-cluster/my-app/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../bases/my-app/
  - namespace.yaml
```

ArgoCD auto-detects Helm charts (presence of `Chart.yaml`) and Kustomize (presence of `kustomization.yaml`) — no explicit `source.helm` or `source.kustomize` config is needed in the ApplicationSet.

---

## Applying cluster-specific patches

Use Kustomize `patches` in the overlay to override base values without modifying the base:

```yaml
# overlay/my-sno-cluster/my-app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../../../bases/my-app/
  - namespace.yaml

patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
    target:
      kind: Deployment
      name: my-app
```

---

## Ignoring runtime-generated fields

If your workload has fields that change at runtime (e.g. a ConfigMap populated by a CronJob), add an `ignoreDifferences` entry to `argocd/appset-workloads.yaml` so ArgoCD does not revert them:

```yaml
ignoreDifferences:
  - group: ""
    kind: ConfigMap
    name: my-app-config
    namespace: my-app
    jsonPointers:
      - /data
```

Gatus uses this pattern — its config ConfigMap is generated at runtime by a discovery CronJob.

---

## Verifying the new workload

After pushing:

```bash
# Check ArgoCD created the Application
oc get application my-app -n openshift-gitops

# Check sync status
oc get application my-app -n openshift-gitops -o jsonpath='{.status.sync.status}'

# Check health
oc get application my-app -n openshift-gitops -o jsonpath='{.status.health.status}'

# Check pods
oc get pods -n my-app
```

---

## Removing a workload

Delete the overlay directory and push:

```bash
git rm -r overlay/my-sno-cluster/my-app/
git commit -m "remove my-app workload"
git push
```

ArgoCD will delete the Application. Because `prune: true` and the resources finalizer are set on workload apps, all Kubernetes resources in the namespace will be deleted automatically. The namespace itself is deleted if it was created by the overlay's `namespace.yaml`.
