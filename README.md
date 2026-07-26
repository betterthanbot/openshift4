# OpenShift 4 GitOps Platform

A community GitOps platform for Single Node OpenShift (SNO) managed entirely via ArgoCD. One `bootstrap.yaml` applied manually seeds the entire platform — operators, operands, and workloads.

---

## What's Included

| Layer | Contents |
|-------|----------|
| **Operators (layer1)** | 14 operators declared, 12 enabled — GitOps and DevWorkspace are off, see [VERSIONS.md](VERSIONS.md) |
| **Operands (layer2)** | Grafana, LokiStack (logging + netobserv), FlowCollector, RHACS, OpenShift AI, NFD, GPU, Compliance, Logging, OpenShift Virtualization (see [tutorial](docs/tutorials/openshift-virtualization-on-ec2.md)) |
| **Workloads** | Gatus, Grafana Dashboards, CTFd *(incomplete — see [techdebt.md](techdebt.md) item 9)*. Kyverno and get-a-username are present in the repo but **excluded** from the workload ApplicationSet — see below |
| **Scripts (not GitOps-managed)** | [MaaS identity & API key provisioning](dumps/identity-management/README.md) — bulk-provisions RHOAI Models-as-a-Service users, subscriptions and keys |

Workloads are discovered by a Git directory generator over `overlay/my-sno-cluster/*`,
so a new subdirectory with a `kustomization.yaml` becomes an ArgoCD Application with no
change to [argocd/appset-workloads.yaml](argocd/appset-workloads.yaml). Two are
explicitly excluded there (`kyverno`, `get-a-username`) — remove the `exclude: true`
entry to bring either back.

> **This branch (`argocd/demo`) points at itself.** `bootstrap/bootstrap.yaml` and both
> ApplicationSets set `targetRevision: argocd/demo`, and none of them enable
> `syncPolicy.automated` — nothing self-heals and nothing prunes, so applications sitting
> `OutOfSync` is the expected steady state here rather than a fault. Change both when you
> fork.

---

## Prerequisites

- OpenShift 4.x cluster (SNO or multi-node)
- `oc` CLI logged in as `cluster-admin`
- `git` CLI
- OpenShift GitOps operator installed on the cluster (pre-installed on most OCP clusters)

Verify GitOps is running:

```bash
oc get pods -n openshift-gitops
```

---

## Quick Start

### 1. Fork and clone this repo

```bash
git clone https://github.com/betterthanbot/openshift4.git
cd openshift4
```

Update the source repo URL in `argocd/appset-operators.yaml` and `argocd/appset-workloads.yaml` to point to your fork.

### 2. Bootstrap ArgoCD

Apply the bootstrap Application once — ArgoCD takes it from here:

```bash
oc apply -f bootstrap/bootstrap.yaml
```

ArgoCD will sync in waves:

| Wave | What happens |
|------|-------------|
| 1 | Namespaces, OperatorGroups, Subscriptions created — operators install |
| 2 | Operator CRs applied (Grafana, LokiStack, RHACS, OpenShift AI, etc.) |
| 3 | Workloads deployed (Gatus, Grafana dashboards, Kyverno) |

Allow 10–15 minutes for all operators to reach `Succeeded` and operands to become `Ready`.

### 3. Enter LokiStack S3 credentials

Two LokiStack instances require separate S3 buckets — one for cluster logging, one for network observability. Placeholder secrets are created by ArgoCD on first sync; fill them in with your real credentials:

```bash
# Cluster Logging LokiStack
oc create secret generic logging-loki-s3 \
  -n openshift-logging \
  --from-literal=access_key_id=<your-access-key-id> \
  --from-literal=access_key_secret=<your-secret-access-key> \
  --from-literal=bucketnames=<your-logging-bucket-name> \
  --from-literal=endpoint=https://s3.<region>.amazonaws.com \
  --from-literal=region=<region> \
  --dry-run=client -o yaml | oc apply -f -

# Network Observability LokiStack
oc create secret generic netobserv-loki-s3 \
  -n netobserv \
  --from-literal=access_key_id=<your-access-key-id> \
  --from-literal=access_key_secret=<your-secret-access-key> \
  --from-literal=bucketnames=<your-netobserv-bucket-name> \
  --from-literal=endpoint=https://s3.<region>.amazonaws.com \
  --from-literal=region=<region> \
  --dry-run=client -o yaml | oc apply -f -
```

ArgoCD will never overwrite these secrets after credentials are entered. See [LokiStack S3 Setup](docs/tutorials/lokistack-s3-setup.md) for full details.

### 4. Configure RHACS (post-install)

After the RHACS operator installs and `Central` is `Ready`, you must generate an init bundle to connect SecuredCluster to Central:

1. Retrieve the RHACS Central route:
   ```bash
   oc get route -n stackrox
   ```

2. Log in to the RHACS UI (default admin credentials are in the `central-htpasswd` secret):
   ```bash
   oc get secret central-htpasswd -n stackrox \
     -o jsonpath='{.data.password}' | base64 -d
   ```

3. In the RHACS UI navigate to **Platform Configuration → Clusters → Create init bundle**

4. Download the init bundle YAML and apply it to your cluster:
   ```bash
   oc apply -f <init-bundle>.yaml -n stackrox
   ```

5. Trigger an ArgoCD sync on `operators-layer2` — SecuredCluster will connect to Central using the bundle.

> The init bundle contains cluster-specific secrets. Do not commit it to git.

### 5. Provision workshop users (get-a-username)

> **Excluded from the workload ApplicationSet by default.** Remove the
> `overlay/my-sno-cluster/get-a-username` `exclude: true` entry in
> [argocd/appset-workloads.yaml](argocd/appset-workloads.yaml) before any of this applies.

`overlay/my-sno-cluster/get-a-username/` deploys the [username-distribution](https://quay.io/openshiftlabs/username-distribution) tool, which hands each attendee a `userN` login and their assigned modules/console links. ArgoCD only ever creates **placeholder** Secrets for this (no real password is committed to git) — after first sync, run the setup script locally:

```bash
# Edit WORKSHOP_PASSWORD at the top of the script first — never commit that edit.
vi bases/get-a-username/init.sh
./bases/get-a-username/init.sh
```

This creates the `userN` namespaces/`User` objects, sets up an `HTPasswd` identity provider on `oauth/cluster` so those accounts can actually log in, points the tool's console/DevSpaces links at this cluster's real routes, and restarts the tool so it picks everything up.

To tear a workshop run down afterward (deletes the namespaces, users, identity provider, and everything attendees deployed inside their namespaces):

```bash
./bases/get-a-username/cleanup.sh
```

See [overlay/my-sno-cluster/get-a-username/README.md](overlay/my-sno-cluster/get-a-username/README.md) for the full workflow.

### 6. Provision MaaS users and API keys (optional)

If the cluster runs RHOAI Models-as-a-Service, one script stands up the whole roster —
htpasswd identities, OpenShift Groups, `MaaSSubscription`s, `MaaSAuthPolicy`s and a
verified API key per user — from a single `config.json`:

```bash
cd dumps/identity-management
./provision-maas-keys.sh --dry-run   # show the plan, change nothing
./provision-maas-keys.sh             # reconcile + mint
```

It is safe to re-run: existing users keep their passwords, existing keys are not
re-issued. Output lands in `dumps/identity-management/out/` (gitignored — it contains
live credentials). [`testing.sh.tmp`](testing.sh.tmp) then drives real inference traffic
through every issued key and tallies it by user, subscription, model and cost centre.

This is deliberately **not** GitOps-managed: it mints credentials, which do not belong in
git. See [dumps/identity-management/README.md](dumps/identity-management/README.md) for
the full flow and the reasoning behind it.

---

## Operator Versions

Every subscription uses `installPlanApproval: Automatic`, so the `startingCSV` in
[operators/layer1-install/values.yaml](operators/layer1-install/values.yaml) is a
**floor, not a pin** — OLM upgrades to the head of the channel from there. Both columns
below are therefore real and usually differ.

| Operator | Channel | `startingCSV` (repo) | Running (2026-07-26) |
|----------|---------|----------------------|----------------------|
| Grafana Community | `v5` | `v5.22.2` | `5.24.0` |
| NVIDIA GPU Operator | `v26.3` | `v26.3.2` | `26.3.3` |
| Cluster Observability | `stable` | `v1.4.0` | `1.5.1` |
| Compliance Operator | `stable` | `v1.8.2` | `1.9.1` |
| Kernel Module Management Hub | `stable` | `v2.6.0` | `2.6.1` *(installing)* |
| Cluster Logging | `stable-6.4` | `v6.4.3` | `6.4.6` |
| Node Feature Discovery | `stable` | `4.20.0-202603051149` | `4.20.0-202607141145` |
| Loki Operator | `stable-6.4` | `v6.4.3` | `6.4.6` |
| Red Hat OpenShift AI | `stable-3.3` *(repo)* | `3.3.2` | `3.4.2` *(on `stable-3.4`)* |
| RHACS | `stable` | `v4.10.0` | `4.11.1` |
| OpenShift Virtualization | `stable` | `v4.20.15` | `4.20.21` |
| Network Observability | `stable` | *(latest)* | `1.12.1` |

RHOAI is the notable gap: the repo tracks `stable-3.3` while the cluster runs `stable-3.4`,
so a rebuild from this repo lands on a different minor version than the one validated here.
Tracked as item 10 in [techdebt.md](techdebt.md).

See [VERSIONS.md](VERSIONS.md) for the full table, operand versions, and upgrade steps.

---

## Post-Install Verification

```bash
# All ArgoCD applications should be Synced + Healthy
oc get applications -n openshift-gitops

# Grafana route
oc get route -n grafana

# RHACS route
oc get route -n stackrox

# LokiStack status (logging)
oc get lokistack -n openshift-logging

# Log collection flowing
oc get clusterlogforwarder -n openshift-logging

# Network Observability — LokiStack + FlowCollector
oc get lokistack -n netobserv
oc get flowcollector cluster

# Compliance scans running
oc get compliancescan -n openshift-compliance
```

---

## Repository Structure

```
bootstrap/          # Apply once to seed ArgoCD
argocd/             # AppProject, ApplicationSets, RBAC
operators/
  layer1-install/   # Helm chart: Namespaces, OperatorGroups, Subscriptions
  layer2-operands/  # Helm chart: Operator CRs / operands
bases/              # Shared Helm/Kustomize bases (gatus, grafana, kyverno, ctfd, get-a-username)
overlay/            # Cluster-specific Kustomize overlays — one dir per workload
docs/               # GitHub Pages documentation
dumps/              # Live cluster resource dumps (MaaS/Kuadrant/RHOAI) kept for reference
  identity-management/   # MaaS user + API key provisioning script (not GitOps-managed)
techdebt.md         # Known issues, workarounds and their root causes — read before debugging
```

---

## Documentation

Full documentation is published via GitHub Pages:

- [Architecture](docs/architecture.md)
- [Getting Started](docs/getting-started.md)
- [Known issues & tech debt](techdebt.md) — current status of every known cluster-side problem
- [MaaS identity & API key provisioning](dumps/identity-management/README.md)
- [Grafana dashboard suite](bases/grafana/dashboard/README.md) — 9 persona-oriented dashboards
- [Tutorials](docs/tutorials/)
  - [Adding a Workload](docs/tutorials/adding-a-workload.md)
  - [Operator Management](docs/tutorials/operator-management.md)
  - [Grafana + Thanos Datasource](docs/tutorials/grafana-thanos-datasource.md)
  - [LokiStack S3 Setup](docs/tutorials/lokistack-s3-setup.md)
  - [Adding GPU Nodes](docs/tutorials/adding-gpu-nodes.md)
  - [OpenShift Virtualization on EC2](docs/tutorials/openshift-virtualization-on-ec2.md)

---

## Uninstall

```bash
oc delete -f bootstrap/bootstrap.yaml
```

ArgoCD cascade deletion is enabled — removing the bootstrap Application will delete all managed Applications and their resources.
