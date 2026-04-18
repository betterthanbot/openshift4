---
title: Operator Management
parent: Tutorials
nav_order: 1
---

# Operator Management

This guide explains how to enable, disable, and configure the operators managed by this repo. All changes are made in YAML files and applied via GitOps — no manual OperatorHub clicks required.

---

## How operators are managed

Operators are split across two Helm charts:

| Chart | Path | Purpose |
|-------|------|---------|
| `layer1-install` | `operators/layer1-install/` | Installs operators via OLM (Namespace + OperatorGroup + Subscription) |
| `layer2-operands` | `operators/layer2-operands/` | Creates operator Custom Resources (instances, configs) |

Each operator has an `enabled:` flag in both charts. Setting `enabled: false` in layer1 prevents installation. Setting it in layer2 prevents operand creation.

---

## Currently managed operators

| Operator | layer1 key | layer2 key | Namespace | Status |
|----------|-----------|-----------|-----------|--------|
| Grafana (Community v5) | `grafana` | `grafana` | `grafana` | ✅ enabled |
| NVIDIA GPU Operator | `gpuOperator` | `gpuOperator` | `nvidia-gpu-operator` | ✅ enabled |
| Cluster Observability | `clusterObservability` | — | `openshift-cluster-observability-operator` | ✅ enabled |
| Compliance Operator | `complianceOperator` | `compliance` | `openshift-compliance` | ✅ enabled |
| KMM Hub | `kmmHub` | — | `openshift-kmm-hub` | ✅ enabled |
| Cluster Logging v6 | `clusterLogging` | `logging` | `openshift-logging` | ✅ enabled |
| Node Feature Discovery | `nfd` | `nfd` | `openshift-nfd` | ✅ enabled |
| Loki Operator | `lokiOperator` | `lokiStack` | `openshift-operators-redhat` | ✅ enabled |
| DevWorkspace | `devWorkspace` | — | `openshift-operators` | ✅ enabled |
| RHODS / OpenShift AI | `rhodsOperator` | `rhods` | `redhat-ods-operator` | ✅ enabled |
| RHACS | `rhacsOperator` | `rhacs` | `stackrox` | ✅ enabled |
| OpenShift GitOps | `gitopsOperator` | `gitops` | `openshift-gitops-operator` | ❌ disabled (pre-installed) |

---

## Disabling an operator

### Step 1 — Disable the operand (layer2)

Open `operators/layer2-operands/values.yaml` and set `enabled: false` for the operator's section.

Example — disable RHACS:
```yaml
rhacs:
  enabled: false   # ← change this
```

### Step 2 — Disable the subscription (layer1)

Open `operators/layer1-install/values.yaml` and set `enabled: false`.

Example — disable RHACS:
```yaml
operators:
  rhacsOperator:
    enabled: false   # ← change this
```

### Step 3 — Commit and push

```bash
git add operators/
git commit -m "disable RHACS operator"
git push
```

ArgoCD will detect the change, remove the Custom Resources first (layer2), then remove the Subscription (layer1). With `prune: false` set on the operator ApplicationSet, ArgoCD will not delete the namespace — remove it manually if desired.

---

## Enabling an operator

### Step 1 — Enable in layer1

Set `enabled: true` in `operators/layer1-install/values.yaml`:

```yaml
operators:
  rhacsOperator:
    enabled: true
```

### Step 2 — Enable in layer2

Set `enabled: true` in `operators/layer2-operands/values.yaml`:

```yaml
rhacs:
  enabled: true
```

### Step 3 — Commit and push

ArgoCD will install the operator (layer1 sync wave 1) and then apply the operand CR (layer2 sync wave 2).

---

## Adding a new operator

### Step 1 — Add to layer1

Add an entry to `operators/layer1-install/values.yaml` following the existing pattern:

```yaml
operators:
  myOperator:
    enabled: true
    namespace:
      create: true
      name: my-operator-namespace
      labels:
        kubernetes.io/metadata.name: my-operator-namespace
    operatorGroup:
      create: true
      name: my-operator
      targetNamespaces: []   # [] = AllNamespaces, or list specific namespaces
    subscription:
      name: my-operator-package-name   # OLM package name from OperatorHub
      namespace: my-operator-namespace
      channel: stable
      source: community-operators       # or redhat-operators, certified-operators
      installPlanApproval: Automatic
      startingCSV: ""                   # leave empty for latest, or pin e.g. "my-operator.v1.2.3"
```

To find the correct `name`, `channel`, and `source`, browse OperatorHub in the OpenShift Web Console or run:

```bash
oc get packagemanifests -n openshift-marketplace | grep <operator-name>
oc get packagemanifest <name> -n openshift-marketplace -o yaml | grep -E "channel|defaultChannel"
```

### Step 2 — Add RBAC for ArgoCD (if needed)

The ArgoCD SA already has `cluster-admin`, so no additional RBAC is required for standard operators.

### Step 3 — Add to layer2 (optional)

If the operator requires Custom Resources to function, create a new template in `operators/layer2-operands/templates/` and add corresponding values in `operators/layer2-operands/values.yaml`. Follow the existing templates as examples.

### Step 4 — Commit and push

---

## Pinning an operator to a specific version

To prevent automatic updates, set `startingCSV` and change `installPlanApproval` to `Manual`:

```yaml
subscription:
  installPlanApproval: Manual
  startingCSV: "my-operator.v1.2.3"
```

With `Manual` approval, OLM will create an `InstallPlan` but wait for human approval before upgrading. Approve via CLI:

```bash
oc get installplan -n <namespace>
oc patch installplan <name> -n <namespace> \
  --type merge -p '{"spec":{"approved":true}}'
```

---

## Changing an operator channel

To track a different release channel, update `channel` in `operators/layer1-install/values.yaml`:

```yaml
subscription:
  channel: stable-6.3   # was stable-6.2
```

Commit and push — OLM will upgrade the operator to the latest CSV in the new channel on the next reconcile.

---

## Compliance Operator — managing scan profiles

Compliance scans are configured in `operators/layer2-operands/values.yaml` under `compliance.scanSettings` and `compliance.scanSettingBindings`. To add a new profile binding:

```yaml
compliance:
  scanSettingBindings:
    - name: my-scan
      namespace: openshift-compliance
      settingsRef: cis-1.7-full    # reference an existing ScanSetting
      profiles:
        - apiGroup: compliance.openshift.io/v1alpha1
          kind: Profile
          name: ocp4-cis-1-7
```

List available profiles:
```bash
oc get profiles.compliance -n openshift-compliance
```
