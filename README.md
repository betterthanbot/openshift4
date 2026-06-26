# OpenShift 4 GitOps Platform

A community GitOps platform for Single Node OpenShift (SNO) managed entirely via ArgoCD. One `bootstrap.yaml` applied manually seeds the entire platform — operators, operands, and workloads.

---

## What's Included

| Layer | Contents |
|-------|----------|
| **Operators (layer1)** | 12 operators installed via OLM |
| **Operands (layer2)** | Grafana, LokiStack (logging + netobserv), FlowCollector, RHACS, OpenShift AI, NFD, GPU, Compliance, Logging |
| **Workloads** | Gatus, Grafana Dashboards, Kyverno |

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

---

## Operator Versions

| Operator | Version | Channel | Source |
|----------|---------|---------|--------|
| Grafana Community | `v5.22.2` | `v5` | community-operators |
| NVIDIA GPU Operator | `v26.3.2` | `v26.3` | certified-operators |
| Cluster Observability | `v1.4.0` | `stable` | redhat-operators |
| Compliance Operator | `v1.8.2` | `stable` | redhat-operators |
| Kernel Module Management Hub | `v2.6.0` | `stable` | redhat-operators |
| Cluster Logging | `v6.4.3` | `stable-6.4` | redhat-operators |
| Node Feature Discovery | `4.20.0` | `stable` | redhat-operators |
| Loki Operator | `v6.4.3` | `stable-6.4` | redhat-operators |
| DevWorkspace Operator | `v0.41.0` | `fast` | redhat-operators |
| Red Hat OpenShift AI | `3.4.1` | `stable-3.4` | redhat-operators |
| RHACS | `v4.11.0` | `stable` | redhat-operators |
| Network Observability | latest | `stable` | redhat-operators |

See [VERSIONS.md](VERSIONS.md) for full version details and upgrade instructions.

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
bases/              # Shared Helm/Kustomize bases (gatus, grafana, kyverno)
overlay/            # Cluster-specific Kustomize overlays
docs/               # GitHub Pages documentation
```

---

## Documentation

Full documentation is published via GitHub Pages:

- [Architecture](docs/architecture.md)
- [Getting Started](docs/getting-started.md)
- [Tutorials](docs/tutorials/)
  - [Adding a Workload](docs/tutorials/adding-a-workload.md)
  - [Operator Management](docs/tutorials/operator-management.md)
  - [Grafana + Thanos Datasource](docs/tutorials/grafana-thanos-datasource.md)
  - [LokiStack S3 Setup](docs/tutorials/lokistack-s3-setup.md)
  - [Adding GPU Nodes](docs/tutorials/adding-gpu-nodes.md)

---

## Uninstall

```bash
oc delete -f bootstrap/bootstrap.yaml
```

ArgoCD cascade deletion is enabled — removing the bootstrap Application will delete all managed Applications and their resources.
