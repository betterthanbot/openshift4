# Kyverno policies — guardrails for a shared cluster

33 ClusterPolicies that let several tenants share this cluster without being
able to reach, starve or impersonate each other. Two more are provided but not
enabled ([optional/](optional/)).

> **Status (2026-11-15):** written and checked offline — `kustomize build`,
> every policy validated against the vendored ClusterPolicy CRD schema, and the
> JMESPath expressions and regular expressions exercised against sample
> objects. They have **not** yet been applied to a cluster or run through the
> Kyverno engine. Follow [Before enabling](#before-enabling) and delete this
> note after the first clean sync.

## The tenant model

A namespace is a tenant namespace when it carries the label
`platform/tenant=<tenant>`. Namespaces with the same value can talk to each
other; namespaces with different values cannot. Every policy here except
`disallow-default-namespace` selects on that label, so a namespace without it is
not affected by anything in this folder.

[tenancy/assign-tenant-label.yaml](tenancy/assign-tenant-label.yaml) sets the
label when a namespace is created:

| How the namespace is created | Tenant |
|---|---|
| By a cluster-admin (`oc create ns`), by Argo CD, or by `kube:admin` with `oc new-project` | First `-` separated part of the name: `acme-prod-api` → `acme`. Names on the platform list in that file are skipped. |
| By a regular user through `oc new-project`, the console or the RHOAI dashboard | The username, if the name starts with `<username>-` (`user1-dev-web` → `user1`). Otherwise the namespace is a tenant of its own. |
| By an operator or any other service account | Not a tenant. |

Self-service projects never join a shared tenant by name, because anyone can run
`oc new-project acme-anything`. Putting a namespace into a shared tenant takes a
cluster-admin or Argo CD.

The label is added only at creation and only if absent. **Namespaces that exist
today are not touched.**

| Namespace label | Set by | Effect |
|---|---|---|
| `platform/tenant=<tenant>` | the policy above, or a cluster-admin | Makes the namespace a tenant namespace |
| `platform/tenant-access=true` | cluster-admin, on a *platform* namespace | Pods in that namespace may connect into every tenant namespace |
| `platform/deletion-protection=enabled` | cluster-admin | The namespace cannot be deleted until the label is removed |

## Policy catalog

**Enforce** blocks the request. **Audit** allows it, records a PolicyReport
entry and returns a warning to the client. **Generate** creates objects in the
namespace. The mode is `validate.failureAction` in each rule.

### [tenancy/](tenancy/)

| Policy | Mode | What it does |
|---|---|---|
| `tenant-assign-namespace-label` | Mutate | Sets `platform/tenant` on new namespaces (table above) |
| `tenant-namespace-naming` | Audit | Name should be `<tenant>-<ns1>-<service>` and start with its tenant |
| `tenant-protect-namespace-labels` | Enforce | Only cluster-admins change the `platform/*` namespace labels |
| `tenant-network-isolation` | Generate | Default-deny ingress, plus allow: same tenant, router, monitoring, API server, `platform/tenant-access` namespaces |
| `tenant-restrict-networkpolicies` | Enforce | Tenant-written NetworkPolicies may not allow ingress from outside the tenant |
| `tenant-default-resourcequota` | Generate | Starting quota: CPU/memory, storage, object counts, no NodePort/LoadBalancer, no GPUs |
| `tenant-default-limitrange` | Generate | Default requests and memory limit for containers, max PVC size |
| `tenant-protect-guardrails` | Enforce | Tenants cannot create, edit or delete the generated `tenant-*` objects |
| `tenant-restrict-kyverno-policies` | Enforce | Tenants cannot author namespaced Kyverno `Policy` / `CleanupPolicy` |
| `protect-namespace-deletion` | Enforce | Opt-in delete protection through a label |

### [pod-security/](pod-security/)

| Policy | Mode | What it does |
|---|---|---|
| `tenant-pod-security-baseline` | Enforce | Pod Security Standard *baseline*: no privileged, host namespaces, hostPath, host ports, extra capabilities |
| `tenant-pod-security-restricted` | Audit | Pod Security Standard *restricted*, background scan of existing pods after SCC admission |
| `tenant-pod-security-restricted-enforce` | Enforce | The same *restricted* profile as a gate on new pods: non-root, no privilege escalation, all capabilities dropped, seccomp |
| `require-user-namespaces` | Enforce | Pods must set `hostUsers: false`, so root in the container is nobody on the node (GPU pods exempt) |
| `restrict-build-strategies` | Enforce | Only S2I builds; no Docker, Custom or JenkinsPipeline builds, which run tenant-controlled steps in a privileged pod |
| `restrict-node-name` | Enforce | No `spec.nodeName` (bypasses the scheduler and taints) |
| `restrict-control-plane-scheduling` | Enforce | No tolerations for control-plane / infra taints, no tolerate-everything |
| `restrict-priority-classes` | Enforce | No `system-*`, `openshift-*`, `kubevirt-*` PriorityClasses (they preempt other tenants) |
| `restrict-ovn-gateway-annotations` | Enforce | No OVN external-gateway pod annotations (can hijack another namespace's egress) |

### [workloads/](workloads/)

| Policy | Mode | What it does |
|---|---|---|
| `disallow-latest-tag` | Audit | Images need a tag, and not `latest` |
| `require-requests-limits` | Audit | Workloads declare their own CPU/memory requests and memory limit |
| `require-probes` | Audit | Every container of a long-running workload has a probe |
| `restrict-image-registries` | Audit | Images come from the registry allow-list |
| `require-ro-rootfs` | Audit | `readOnlyRootFilesystem: true` |
| `restrict-pdb-zero-disruption` | Enforce | No PodDisruptionBudget that blocks node drains and cluster upgrades |
| `disallow-default-namespace` | Audit | No workloads in `default` |

### [exposure/](exposure/)

| Policy | Mode | What it does |
|---|---|---|
| `restrict-service-exposure` | Enforce | No NodePort / LoadBalancer Services, no `externalIPs` |
| `restrict-route-ingress-hosts` | Enforce | Route and Ingress hostnames must contain the namespace name; no wildcard Routes |
| `require-route-tls` | Audit | Routes terminate TLS and do not also serve plain HTTP |

### [rbac/](rbac/)

| Policy | Mode | What it does |
|---|---|---|
| `restrict-clusteradmin-rolebindings` | Enforce | No RoleBinding to `cluster-admin` in a tenant namespace |
| `restrict-cross-tenant-rolebindings` | Enforce | No RoleBinding to a service account from another tenant |
| `audit-risky-roles` | Audit | Roles with wildcard verbs/resources or `bind` / `escalate` / `impersonate` |
| `audit-elevated-scc-bindings` | Audit | Lists SCC grants stronger than restricted-v2 / nonroot-v2 |

### [optional/](optional/) — not enabled

| Policy | What it does |
|---|---|
| `require-sandboxed-runtime` | Every tenant pod must run under the `kata` / `kata-remote` RuntimeClass, giving each pod its own kernel. Needs the OpenShift sandboxed containers Operator and nodes that can run VMs — read the file header. |
| `tenant-egress-isolation` | Default-deny egress with allows for DNS, same tenant, outside the cluster and labelled platform namespaces. Breaks builds and calls to shared services until those namespaces are labelled — read the file header. |

`kyverno-rbac.yaml` is not a policy: it lets Kyverno's reports controller read
Roles and RoleBindings so the `rbac/` policies can report on existing objects.

## Common tasks

**Remove a policy** — delete its line in the folder's `kustomization.yaml`.
Remove a whole group by deleting the folder's line in
[kustomization.yaml](kustomization.yaml). Keep `tenant-assign-namespace-label`
unless you label namespaces yourself; without it nothing else applies to new
namespaces.

**Onboard a namespace that already exists**

```bash
oc label namespace <ns> platform/tenant=<tenant>
```

The NetworkPolicies, quota and LimitRange appear within seconds. Enforced
policies apply to the next change; running pods are not evicted.

**Create a platform or operator namespace by hand or through Argo CD** — add
its name to the list in
[tenancy/assign-tenant-label.yaml](tenancy/assign-tenant-label.yaml) first.
If it was onboarded by accident:

```bash
oc label namespace <ns> platform/tenant-
oc delete resourcequota/tenant-default-quota limitrange/tenant-default-limits -n <ns>
```

Kyverno removes the generated NetworkPolicies itself; the quota and LimitRange
are created once and must be deleted by hand.

**Let a shared platform service call into tenant namespaces** (a gateway, RHOAI
controllers, a mesh control plane):

```bash
oc label namespace <platform-ns> platform/tenant-access=true
```

**Raise a tenant's quota** — `oc edit resourcequota tenant-default-quota -n <ns>`
as cluster-admin. Kyverno does not revert it. Change the defaults for future
namespaces in [tenancy/default-resourcequota.yaml](tenancy/default-resourcequota.yaml).

**Turn an Audit policy into Enforce** (or back) — change `failureAction` in the
rule. Check the reports first:

```bash
oc get policyreport -A
oc get policyreport -n <ns> -o yaml
```

**Exempt a workload** — PolicyExceptions are switched off in this install
(`--enablePolicyException=false` in `kyverno.yaml`), so exemptions are `exclude`
entries in the policy. To use PolicyExceptions instead, set
`features.policyExceptions.enabled: true` and `namespace: kyverno` in
`../values.yaml` and re-render with `make kyverno`.

## Before enabling

1. **Kyverno is not deployed.** `overlay/my-sno-cluster/kyverno` is excluded in
   [argocd/appset-workloads.yaml](../../../argocd/appset-workloads.yaml).
   Remove the two `exclude` lines to create the Application.
2. **`generate-vpa.yaml` needs the VerticalPodAutoscaler CRD**, which was not
   installed on the cluster when this was written. Kyverno will reject that one
   policy and the sync will report a failure until the VPA operator is
   installed or the policy is removed. The other policies are unaffected.
3. **Run more than one Kyverno replica.** The chart defaults render one replica
   of each controller. Once policies match Pods, Services and Namespaces,
   the API server calls Kyverno for those requests in every namespace except
   `kube-system` and `kyverno`, and by default a request fails if Kyverno does
   not answer. One evicted pod during a node drain then blocks pod creation
   cluster-wide, including in `openshift-*`. Set `admissionController.replicas: 3`
   in `../values.yaml` and re-render with `make kyverno`.
4. **Try it on one throwaway namespace** before onboarding anything real:

   ```bash
   oc create namespace acme-test-web            # as cluster-admin
   oc get namespace acme-test-web --show-labels # expect platform/tenant=acme
   oc get networkpolicy,resourcequota,limitrange -n acme-test-web
   oc get clusterpolicy                         # every policy READY=True
   ```

   Then, as a non-admin user, run `oc new-project acme-test-evil` and confirm it
   is labelled `platform/tenant=acme-test-evil`, not `acme`.

## Known interactions

- **Tenant workloads must opt in to user namespaces.** `require-user-namespaces`
  rejects any Deployment, StatefulSet, Job or Pod whose pod spec lacks
  `hostUsers: false`. Nothing fills that field in, so off-the-shelf Helm charts
  and operators installed into a tenant namespace need it set. Volumes on NFS
  may not work in a user namespace.
- **Workloads that need root or an `anyuid` grant** are blocked by
  `tenant-pod-security-restricted-enforce`, whatever SCC they were given.
- **OpenShift builds.** Build pods are privileged. `tenant-pod-security-baseline`
  exempts the build controller, as OpenShift's own Pod Security Admission does.
  They still count against the tenant's quota.
- **Admins using `oc new-project`.** Only `kube:admin` and `system:admin` are
  recognised as platform admins on that path. Other cluster-admins should use
  `oc create namespace`, or add their username to the list in
  `assign-tenant-label.yaml`.
- **Operators installed into a tenant namespace** run under the tenant
  guardrails. The API server can reach their webhooks; anything else that calls
  in from a platform namespace needs `platform/tenant-access=true` on it.
- **RHOAI data science projects** are created as self-service projects, so each
  becomes a tenant of its own with the default quota (no GPUs). Label
  `redhat-ods-applications` with `platform/tenant-access=true` if its
  controllers need to reach workloads there.
- **OpenShift Virtualization.** VM (`virt-launcher`) pods have not been checked
  against `tenant-pod-security-baseline`. Test a VM in a tenant namespace
  before relying on it.

## Limits

- **Tenants still share the node's kernel.** The pod-security policies remove
  the known ways out of a container and make an escape land without host
  privileges, but they cannot stop a kernel vulnerability reachable through
  the allowed system calls. Only a sandboxed runtime does
  (`optional/require-sandboxed-runtime.yaml`).
- **Egress is not restricted** unless the optional policy is enabled. Tenant
  pods can connect to platform namespaces that have no NetworkPolicy of their
  own.
- **Cluster-admins and Argo CD are exempt** from the policies that have a
  cluster-admin exclusion (NetworkPolicy content, Route hostnames, cross-tenant
  RoleBindings, guardrail and label protection). What Argo CD deploys into a
  tenant namespace is trusted.
- **Cross-tenant RBAC is only checked for service accounts.** Kubernetes has no
  record of which tenant a user or group belongs to.
- **Renaming the label** means replacing `platform/tenant` in every file in this
  folder; the policies have no shared variable for it.
