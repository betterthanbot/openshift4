# `operators/` — one base, one overlay and one ArgoCD app per operator

Everything that installs and configures an OpenShift operator lives here. Each operator is
a self-contained **bundle** — the OLM install (Namespace, OperatorGroup, Subscription)
*and* the custom resources that configure it — and each bundle is its own Application in
the ArgoCD UI:

```
operators-grafana-operator   operators-gpu-operator   operators-rhoai   operators-maas   …
```

This replaced two Helm charts, `layer1-install` (every Subscription) and `layer2-operands`
(every operand), which showed up as just `operators-layer1` and `operators-layer2`.

## Layout

```
operators/
  bases/<name>/                      what to deploy — cluster-agnostic
    kustomization.yaml               header: what it is, what it installs, what it needs
    namespace.yaml                   ┐
    operatorgroup.yaml               │ the operator            sync waves -3 / -2 / -1
    subscription.yaml                ┘
    <operand>.yaml …                 its custom resources      wave 0 and up
  overlay/my-sno-cluster/<name>/     what THIS cluster changes — the ArgoCD app points here
    kustomization.yaml               ../../../bases/<name> + any cluster-specific patches
```

`argocd/appset-operators.yaml` runs a git-directory generator over
`operators/overlay/my-sno-cluster/*` and creates one Application, `operators-<name>`, per
directory. Workloads keep their own tree (`bases/` + `overlay/`) and their own
ApplicationSet; the two never overlap.

## The apps

### Enabled (20)

| App | Base | Contents | Namespace | Sync these first |
|---|---|---|---|---|
| `operators-loki` | [`bases/loki`](bases/loki) | Loki operator (provides the `LokiStack` CRD) | `openshift-operators-redhat` | — |
| `operators-service-mesh` | [`bases/service-mesh`](bases/service-mesh) | Service Mesh 3 / Sail operator | `openshift-operators` | — |
| `operators-opentelemetry` | [`bases/opentelemetry`](bases/opentelemetry) | OpenTelemetry operator | `openshift-opentelemetry-operator` | — |
| `operators-tempo` | [`bases/tempo`](bases/tempo) | Tempo operator | `openshift-tempo-operator` | — |
| `operators-leader-worker-set` | [`bases/leader-worker-set`](bases/leader-worker-set) | Leader Worker Set operator | `openshift-lws-operator` | — |
| `operators-cluster-observability` | [`bases/cluster-observability`](bases/cluster-observability) | Cluster Observability operator + the logging `UIPlugin` | `openshift-cluster-observability-operator` | cluster-logging (runtime only) |
| `operators-nfd` | [`bases/nfd`](bases/nfd) | NFD operator + `NodeFeatureDiscovery` | `openshift-nfd` | — |
| `operators-gpu-operator` | [`bases/gpu-operator`](bases/gpu-operator) | NVIDIA GPU operator + `ClusterPolicy` | `nvidia-gpu-operator` | nfd |
| `operators-compliance` | [`bases/compliance`](bases/compliance) | Compliance operator + `ScanSetting`s / `ScanSettingBinding`s | `openshift-compliance` | — |
| `operators-rhacs` | [`bases/rhacs`](bases/rhacs) | RHACS operator + `Central` + `SecuredCluster` | `stackrox` | — |
| `operators-cnv` | [`bases/cnv`](bases/cnv) | OpenShift Virtualization + `HyperConverged` | `openshift-cnv` | — |
| `operators-kueue` | [`bases/kueue`](bases/kueue) | Kueue operator + `Kueue` | `openshift-kueue-operator` | cert-manager (sandbox-provided here) |
| `operators-connectivity-link` | [`bases/connectivity-link`](bases/connectivity-link) | RHCL operator + `Kuadrant` (+ `kuadrant-system` namespace) | `openshift-operators`, `kuadrant-system` | — |
| `operators-grafana-operator` | [`bases/grafana-operator`](bases/grafana-operator) | Grafana operator + `Grafana`, datasources, token-minting Job | `grafana` | cluster-logging, rhoai, maas (runtime only) |
| `operators-netobserv` | [`bases/netobserv`](bases/netobserv) | Network Observability + its `LokiStack` + `FlowCollector` | `netobserv` | loki |
| `operators-cluster-logging` | [`bases/cluster-logging`](bases/cluster-logging) | Logging operator + `LokiStack` + `ClusterLogForwarder` | `openshift-logging` | loki |
| `operators-rhoai` | [`bases/rhoai`](bases/rhoai) | RHODS operator + `DSCInitialization`, `DataScienceCluster`, `OdhDashboardConfig` | `redhat-ods-operator` | service-mesh, connectivity-link, opentelemetry, tempo |
| `operators-storageclass` | [`bases/storageclass`](bases/storageclass) | `gp3-csi-immediate` StorageClass | — (cluster-scoped) | — |
| `operators-cluster-monitoring` | [`bases/cluster-monitoring`](bases/cluster-monitoring) | user-workload monitoring + RHOAI monitoring workarounds | `openshift-monitoring`, `redhat-ods-monitoring` | rhoai |
| `operators-maas` | [`bases/maas`](bases/maas) | Gateway, `Tenant`, subscriptions, auth + rate-limit policies, metrics DB | `models-as-a-service` (writes into `openshift-ingress`, `redhat-ods-applications`, `kuadrant-system`) | rhoai; connectivity-link; service-mesh; storageclass; a TLS Secret `cert-manager-ingress-cert` in openshift-ingress (not in this repo) |

### Disabled (7)

These have a base and an overlay, but are listed with `exclude: true` in
`argocd/appset-operators.yaml`, so no Application is created. Delete the entry to enable one.

| App | Base | Contents | Namespace | Sync these first |
|---|---|---|---|---|
| `operators-gitops` | [`bases/gitops`](bases/gitops) | GitOps operator + `ArgoCD` CR + AppProjects | `openshift-gitops-operator` | — |
| `operators-workshop-auth` | [`bases/workshop-auth`](bases/workshop-auth) | HTPasswd identity provider on `OAuth/cluster` | `openshift-config` | — |
| `operators-cert-manager` | [`bases/cert-manager`](bases/cert-manager) | cert-manager operator | `cert-manager-operator` | — |
| `operators-kmm-hub` | [`bases/kmm-hub`](bases/kmm-hub) | KMM Hub operator | `openshift-kmm-hub` | — |
| `operators-devworkspace` | [`bases/devworkspace`](bases/devworkspace) | DevWorkspace operator | `openshift-operators` | — |
| `operators-lightspeed` | [`bases/lightspeed`](bases/lightspeed) | OpenShift Lightspeed operator | `openshift-lightspeed` | — |
| `operators-quay` | [`bases/quay`](bases/quay) | Quay operator | `openshift-operators` | — |

*"Sync these first"* lists apps whose CRDs, namespaces or runtime data this one uses. It is
a soft dependency — see the next section.

## How a sync behaves

**Inside an app**, sync waves do the ordering:

| Wave | What |
|------|------|
| -3 | `Namespace` |
| -2 | `OperatorGroup` |
| -1 | `Subscription`. ArgoCD ships a health check for OLM Subscriptions (Healthy once `status.state` is `AtLatestKnown`), so the sync waits here until OLM has installed the operator and registered its CRDs |
| 0 and up | the operand CRs, in the waves they already had (Grafana datasources 2, the token Job 3, MaaS policies 5, …) |

**Between apps there is no ordering.** Sync waves only order the resources of one
Application, and these Applications are created directly by the ApplicationSet controller,
so nothing syncs *them* in waves. An app that needs another app's CRDs simply retries
(`limit: 10`, 30s → 3m backoff, about 24 minutes) until they exist. The old
`operators-layer1` → `operators-layer2` split had the same property — the `sync-wave`
annotations sat on Applications that the ApplicationSet controller creates directly, so they
ordered nothing. What changed is that an operator and its own operands are now in one sync,
where waves do work.

An order that avoids the retries on a fresh cluster:

1. no prerequisites: `storageclass`, `loki`, `service-mesh`, `opentelemetry`, `tempo`,
   `connectivity-link`, `nfd`, `compliance`, `rhacs`, `cnv`, `cluster-observability`,
   `leader-worker-set`
2. `gpu-operator` (after `nfd`), `cluster-logging` and `netobserv` (after `loki`), `kueue`,
   `grafana-operator`
3. `rhoai` (after `service-mesh`, `connectivity-link`, `opentelemetry`, `tempo`)
4. `maas` and `cluster-monitoring` (after `rhoai`)

Nothing is `automated`, so sync by hand in the UI, or all at once:

```bash
argocd app sync -l app.kubernetes.io/part-of=openshift4-operators
```

### Why every operand carries `SkipDryRunOnMissingResource`

On a cold bootstrap an operand's CRD does not exist until the Subscription in the *same*
app has been installed — and ArgoCD rejects a whole sync up front if any rendered kind is
unknown. So every operand CR in `bases/*` carries

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true
```

It has to be per resource; the app-level option on its own did not work (techdebt.md #14).
Forget it on a new operand and a cold-bootstrap sync fails with `one or more synchronization
tasks are not valid` and **nothing** applied — not even the Subscription. (It goes unnoticed
on a cluster where the CRD already exists, which is why it is easy to forget.)

## Everyday tasks

**Change a setting.** Edit the operand file in `bases/<name>/`. If the value is different
per cluster, patch it in the overlay instead — see the MaaS gateway hostname
(`overlay/my-sno-cluster/maas`) and the CNV emulation annotation
(`overlay/my-sno-cluster/cnv`). `grep -rn "CHANGE ME" operators/` lists the values meant to
be changed per cluster.

**Bump an operator.** Edit `channel` / `startingCSV` in `bases/<name>/subscription.yaml`.
`startingCSV` is a floor, not a pin — see [VERSIONS.md](../VERSIONS.md). Keep that file's
tables in step.

**Disable an operator.** Add an `exclude: true` entry for its overlay in
`argocd/appset-operators.yaml`. Because the ApplicationSet sets
`preserveResourcesOnDeletion: true`, this only stops managing it — the operator and its
operands keep running. To actually uninstall, delete the app *with cascade* first
(`argocd app delete operators-<name> --cascade`: removes the Subscription, operands and
Namespace), then exclude it, then remove the leftover CSV (`oc delete csv -n <ns> <csv>`).

**Enable one.** Remove its `exclude: true` entry and sync the new Application.

**Add an operator.**

1. `mkdir operators/bases/<name>` and copy `namespace.yaml`, `operatorgroup.yaml` and
   `subscription.yaml` from a similar operator (`nfd` for operator + one CR, `loki` for
   operator only). Waves: Namespace `-3`, OperatorGroup `-2`, Subscription `-1`. For
   `openshift-operators` there is no Namespace/OperatorGroup — see `service-mesh`.
   To find `name`/`channel`/`source`: `oc get packagemanifest <name> -n openshift-marketplace -o yaml`.
2. Add the operand CRs. Give every one `SkipDryRunOnMissingResource=true` (above). Leave
   waves unset unless the CRs must be ordered among themselves — they run after the
   Subscription either way.
3. Write `kustomization.yaml` listing the files (copy a header from a sibling).
4. `mkdir operators/overlay/my-sno-cluster/<name>` with a `kustomization.yaml` containing
   `resources: [../../../bases/<name>]`.
5. `kustomize build operators/overlay/my-sno-cluster/<name>` to check it, push, and the
   ApplicationSet creates `operators-<name>`. No ArgoCD file needs editing.

**Make one app out of several operators.** An overlay may list more than one base. For a
single `logging` app: create `overlay/my-sno-cluster/logging/kustomization.yaml` with
`resources:` pointing at `bases/cluster-logging`, `bases/loki` and
`bases/cluster-observability`, then exclude those three overlays. Each Namespace must stay
declared in exactly one base.

**Add another cluster.** Copy `overlay/my-sno-cluster` to `overlay/<cluster>`, patch its
per-cluster values, and generate its Applications from a second ApplicationSet (or a second
generator entry with that path and the cluster's `destination.server`).

## Cluster-specific values

| Where | What | Why |
|---|---|---|
| `overlay/my-sno-cluster/maas` | gateway `hostname` | resolves to this cluster's ingress; changes with every new sandbox |
| `overlay/my-sno-cluster/cnv` | `useEmulation` annotation | AWS nodes without `.metal` hardware have no `/dev/kvm` |
| `overlay/my-sno-cluster/rhoai` | `vllm-project` Namespace | where the demo models run |
| `bases/**` marked `CHANGE ME` | RHACS `clusterName`, StorageClass names, S3 secret placeholders, MaaS tiers | portable defaults that you are expected to review |

## Moving an existing cluster off `operators-layer1` / `operators-layer2`

A fresh cluster needs none of this: apply `bootstrap/bootstrap.yaml`, sync `bootstrap`, then
sync the apps. An *existing* cluster does, because of one thing:

> The ApplicationSet controller puts the `resources-finalizer.argocd.argoproj.io` finalizer
> on every Application it generates unless `preserveResourcesOnDeletion` is true. The old
> ApplicationSet had it `false`, so **`operators-layer1` and `operators-layer2` currently
> cascade-delete everything they manage when they go away** — every Subscription,
> OperatorGroup and Namespace, every LokiStack, the DataScienceCluster, Central, Grafana…
> Replacing the ApplicationSet makes the controller delete those two Applications.

So protect them first. Nothing below changes the cluster except the ApplicationSet flag and
the finalizer.

```bash
# 0. Look. Expect FINALIZERS to show resources-finalizer.argocd.argoproj.io today.
oc get applications.argoproj.io operators-layer1 operators-layer2 -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,FINALIZERS:.metadata.finalizers

# 1. Stop the controller adding the finalizer (takes effect immediately; git is not touched).
oc patch applicationset openshift4-operators -n openshift-gitops --type merge \
  -p '{"spec":{"syncPolicy":{"preserveResourcesOnDeletion":true}}}'

# 2. Give the controller a few seconds, then check: the column should now read <none>.
oc get applications.argoproj.io operators-layer1 operators-layer2 -n openshift-gitops \
  -o custom-columns=NAME:.metadata.name,FINALIZERS:.metadata.finalizers
#    Still listed? Remove the finalizer by hand (idempotent — harmless if already empty):
for a in operators-layer1 operators-layer2; do
  oc patch applications.argoproj.io $a -n openshift-gitops --type merge \
    -p '{"metadata":{"finalizers":null}}'
done
#    ...and run the `oc get` above once more to confirm <none> for both.

# 3. Snapshot what is installed, to compare afterwards.
oc get subscription,csv -A -o name | sort > /tmp/operators-before.txt
```

Only when the FINALIZERS column reads `<none>` for both Applications:

4. Merge/push this change and **sync the `bootstrap` Application**. The ApplicationSet now
   generates the `operators-*` Applications and deletes the two old ones — without touching
   what they deployed.
5. Re-run step 3 into `/tmp/operators-after.txt` and `diff` the two files: they must match.
6. Sync the new Applications (order above). They adopt the existing objects in place, so the
   first syncs should be close to no-ops: Helm labels disappear, `sync-wave` /
   `SkipDryRunOnMissingResource` annotations appear, the tracking label moves to the new
   app. Anything that wants to change something else deserves a look.

Rolling back before step 6 is a `git revert` plus a bootstrap sync; nothing was ever
deleted, so there is nothing to restore.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| sync sits on `waiting for healthy state of operators.coreos.com/Subscription/…` | OLM has not finished: `oc get subscription,installplan,csv -n <ns>`. A `Manual`-approval Subscription needs its InstallPlan approved; `CatalogSourcesUnhealthy` means check `oc get catalogsource -n openshift-marketplace` |
| `one or more synchronization tasks are not valid`, 0 resources synced | an operand is missing `SkipDryRunOnMissingResource=true`, or the kustomization does not build — run `kustomize build` on the overlay |
| operand shows `no matches for kind … in version …` and retries | another app's CRD is not there yet — see "Sync these first"; sync that app, then this one |
| app `Failed` after ~24 min | retries ran out waiting on a dependency; sync it again |
| `SharedResourceWarning` | two apps declare the same object. Each object belongs to exactly one base — expected only briefly during the cutover above |
