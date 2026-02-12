# Bootstrap — GitOps Entry Point

## Overview

The **bootstrap** configuration is the entry point that enables GitOps management for this repository.

It is designed to be applied **once** to a cluster after the OpenShift GitOps Operator is installed. After bootstrap is applied, Argo CD will automatically synchronize and manage all platform configuration stored in this repository.

In simple terms:

> Bootstrap teaches Argo CD how to manage itself and the rest of the cluster using Git as the single source of truth.

---

## Why Bootstrap Exists

Bootstrap solves several important platform engineering challenges:

* Enables full **Configuration as Code**
* Ensures **cluster reproducibility**
* Supports **disaster recovery**
* Removes manual configuration drift
* Provides an auditable change history through Git

Instead of manually applying configuration using CLI commands, bootstrap allows Argo CD to continuously reconcile cluster state with this repository.

---

## How Bootstrap Works

### Step 1 — Operator Installation

Install the OpenShift GitOps Operator on the cluster.

This installs:

* Argo CD controllers
* GitOps UI
* Application management components

---

### Step 2 — Apply Bootstrap (Manual One-Time Step)

Bootstrap is intentionally applied manually once:

```
oc apply -f bootstrap/bootstrap.yaml
```

This creates a single Argo CD `Application` resource named `bootstrap`.

---

### Step 3 — Bootstrap Syncs Git Repository

The bootstrap application instructs Argo CD to monitor and deploy resources from:

```
/argocd
```

Inside that folder, Argo CD manages:

* RBAC permissions
* AppProjects
* Applications
* ApplicationSets
* Platform policies
* Future GitOps configuration

---

### Step 4 — Argo CD Takes Over

After bootstrap is applied:

* Argo CD automatically synchronizes changes from Git
* New resources added to `/argocd` are deployed automatically
* Platform configuration becomes fully declarative

---

## Repository Layout

```
bootstrap/
   bootstrap.yaml            ← Manual entry point

argocd/
   rbac/                     ← Argo CD permissions
   projects/                 ← GitOps project boundaries
   applications/             ← Individual workload deployments
   applicationsets/          ← Application factories / scaling patterns

overlay/
   my-sno-cluster/           ← Workload configuration
```

---

## What Bootstrap Does NOT Manage

Bootstrap only initializes GitOps control.

Bootstrap intentionally does not:

* Deploy workloads directly
* Manage application overlays
* Contain business or platform configuration logic

Those responsibilities belong inside the `argocd/` and `overlay/` folders.

---

## Disaster Recovery Workflow

Bootstrap allows full platform recovery using Git.

Recovery steps:

1. Install OpenShift GitOps Operator
2. Apply bootstrap configuration
3. Argo CD restores cluster configuration automatically

This enables rapid cluster rebuilds and consistent platform deployment.

---

## Updating Platform Configuration

To update GitOps-managed configuration:

1. Modify files inside the `argocd/` directory
2. Submit a Pull Request
3. After merge, Argo CD will automatically synchronize changes

No manual cluster changes should be required.

---

## Best Practices

* Keep bootstrap minimal and stable
* Store platform configuration inside `argocd/`
* Store workloads inside `overlay/`
* Use Git pull requests for all changes
* Avoid manual cluster configuration whenever possible

---

## When To Modify Bootstrap

Bootstrap typically only changes when:

* Repository location changes
* Git branch strategy changes
* Argo CD instance namespace changes
* Major GitOps architecture refactoring occurs

---

## Summary

Bootstrap establishes GitOps control for this repository by linking Argo CD to the platform configuration stored in Git.

Once bootstrap is applied, the cluster continuously reconciles against repository state, ensuring consistency, traceability, and reproducibility.

---
