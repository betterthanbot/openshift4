# `argocd/` — What Bootstrap Hands Over To

`bootstrap/bootstrap.yaml` creates exactly one Application, pointed at this directory.
Everything ArgoCD manages afterwards is declared here, so this is the one folder where
adding a file changes what the cluster runs.

New to ArgoCD itself? Start with [docs/architecture.md](../docs/architecture.md) and
[docs/getting-started.md](../docs/getting-started.md) — this file covers only how *this*
repo is wired.

```
argocd/
  appProject.yaml         AppProject: openshift4-community — the trust boundary
  rbac-operands.yaml      ClusterRole/Binding letting ArgoCD create operator CRs
  appset-operators.yaml   ApplicationSet → operators-layer1, operators-layer2
  appset-workloads.yaml   ApplicationSet → one Application per overlay/my-sno-cluster/*
```

## The two ApplicationSets

**`appset-operators.yaml`** uses a *list* generator with two fixed entries, because the
ordering matters: `operators-layer1` (sync-wave 1) creates Namespaces, OperatorGroups and
Subscriptions; `operators-layer2` (sync-wave 2) creates the operand CRs that need those
operators' CRDs to exist first. Both are Helm charts under `operators/`.

**`appset-workloads.yaml`** uses a *git directory* generator over
`overlay/my-sno-cluster/*` at sync-wave 3. Every subdirectory containing a
`kustomization.yaml` becomes its own Application named after the directory — so adding a
workload needs no edit to this file at all:

```bash
mkdir overlay/my-sno-cluster/<name>   # + kustomization.yaml, push
```

To take a workload out of rotation without deleting it, add an exclusion instead:

```yaml
directories:
  - path: overlay/my-sno-cluster/*
  - path: overlay/my-sno-cluster/<name>
    exclude: true
```

`kyverno` and `get-a-username` are currently excluded this way.

## Things that will surprise you

**Nothing syncs itself.** `syncPolicy.automated` is commented out in both
ApplicationSets. Applications go `OutOfSync` on every repo change and stay there until
someone syncs — deliberate on this branch, but it means `OutOfSync` carries no signal
about health.

**The revision is `argocd/demo`, in three places.** `bootstrap/bootstrap.yaml` and both
ApplicationSets each pin `repoURL` and `targetRevision` independently. Forking means
changing all three.

**`ignoreDifferences` protects two runtime-mutated objects.** `gatus-config` is generated
by a discovery CronJob at runtime, and `get-a-username-secret` holds a real password set
by hand on the cluster. Both are declared in `appset-workloads.yaml` so ArgoCD does not
keep reverting them. Add an entry here for any object the cluster is expected to own more
authoritatively than git does.

**`orphanedResources.warn: true`** in `appProject.yaml` is why every workload Application
shows `OrphanedResourceWarning: 134 orphaned resources`. Those namespaces contain plenty
ArgoCD did not create. It is noise, not a fault — turn the flag off if it stops being
useful.

**The AppProject is deliberately wide open** — `clusterResourceWhitelist` and
`namespaceResourceWhitelist` are both `*`/`*`, and destinations allow every namespace.
The file says to tighten this once the cluster is stable; that has not happened yet.

## `rbac-operands.yaml`

ArgoCD's controller does not get permission to create arbitrary operator CRs by default.
This grants it exactly the API groups layer2 needs — Grafana, NVIDIA ClusterPolicy,
DataScienceCluster/DSCInitialization, RHACS Central/SecuredCluster, Compliance scan
settings, ClusterLogForwarder, LokiStack, NodeFeatureDiscovery, plus the core
ServiceAccount/Secret/RBAC/Job verbs those charts use.

**Adding a new operand kind to `layer2-operands` usually means adding its API group
here.** The symptom when you forget is a sync failure naming the group as forbidden, not
a missing CRD.

---

See also: [bootstrap/README.md](../bootstrap/README.md) for how this directory is
reached, and [techdebt.md](../techdebt.md) item 9 for the current sync state of each
Application.
