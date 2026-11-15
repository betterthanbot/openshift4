# Kyverno policy catalog — why each policy exists

Audience: platform owners and reviewers deciding which policies to keep on a
**single OpenShift cluster shared by several tenants**. For how the tenant model
works and how to operate the policies, see [README.md](README.md).

Context that applies to every entry: tenants share one control plane, one
network, one set of nodes and one API server. Namespaces are the only boundary,
and by default that boundary is weak. OpenShift lets any authenticated user
create projects, gives each project admin broad rights inside it, and allows all
pod-to-pod traffic across namespaces. These policies close those gaps.

**Mode:** *Enforce* blocks the request. *Audit* allows it and reports it.
*Generate* creates objects. *Mutate* changes the request.

---

## Category: Multi-Tenancy

| Policy | Mode | What it does | Why it belongs on a shared cluster |
|---|---|---|---|
| `tenant-assign-namespace-label` | Mutate | Labels new namespaces `platform/tenant=<tenant>`: from the name when an admin or Argo CD creates it, from the username (or the namespace itself) for self-service projects. | Every other tenant policy keys off this label, so it is the definition of "who is a tenant". Deriving it from the creator, not just the name, stops a user running `oc new-project acme-anything` and joining another tenant's network. |
| `tenant-namespace-naming` | Audit | Reports tenant namespaces not named `<tenant>-<ns1>-<service>` or whose name disagrees with their tenant label. | The name is the human-visible record of ownership. A mismatch usually means a namespace was labelled into the wrong tenant by hand, which silently grants it network access to that tenant. |
| `tenant-protect-namespace-labels` | Enforce | Only cluster-admins may set or change `platform/tenant`, `platform/tenant-access` and `platform/deletion-protection`; non-admins cannot pick a tenant at creation. | If a tenant could edit its own label it could move itself into another tenant, defeating network isolation, quotas and every other guardrail. |
| `tenant-network-isolation` | Generate | Creates default-deny ingress in each tenant namespace, with allows for the same tenant, the router, monitoring, the API server and labelled platform namespaces. | OpenShift's default network is flat: any pod can reach any other pod. This is the control that actually delivers "same tenant can talk, different tenants cannot". |
| `tenant-restrict-networkpolicies` | Enforce | Blocks tenant NetworkPolicies that allow ingress from outside the tenant (no source, other namespace selectors, ipBlock). | NetworkPolicies are additive and project admins can create them. Without this, one tenant publishes "allow from everywhere" and the isolation above is gone. |
| `tenant-default-resourcequota` | Generate | Creates a starting quota: CPU, memory, storage, object counts, no NodePort/LoadBalancer, no GPUs. | Nodes are shared. Without quotas one tenant can consume the cluster's capacity (the "noisy neighbour") or the scarce GPUs. |
| `tenant-default-limitrange` | Generate | Gives containers default requests and a default memory limit, and caps PVC size. | A quota rejects pods that set no resources. This lets them start with small, predictable defaults instead of unbounded ones. |
| `tenant-protect-guardrails` | Enforce | Only cluster-admins and Kyverno may create, edit or delete objects named `tenant-*` in tenant namespaces. | Tenant admins have rights on NetworkPolicy, quota and LimitRange objects. Without this they could simply delete their own guardrails. |
| `tenant-restrict-kyverno-policies` | Enforce | Blocks tenants from creating or changing namespaced Kyverno `Policy` and `CleanupPolicy`. | The chart grants these kinds to the `admin` role, and they run with Kyverno's privileges. A tenant `CleanupPolicy` could delete the platform's guardrails on a schedule. |
| `protect-namespace-deletion` | Enforce | Opt-in: a namespace labelled `platform/deletion-protection=enabled` cannot be deleted until the label is removed. | A project admin can delete their whole project, with every workload, secret and PVC. Gives shared databases and similar namespaces a safety catch against accidents. |

## Category: Pod Security

| Policy | Mode | What it does | Why it belongs on a shared cluster |
|---|---|---|---|
| `tenant-pod-security-baseline` | Enforce | Applies the Pod Security *baseline* profile: no privileged containers, host namespaces, hostPath, host ports or extra capabilities. | A privileged or host-level pod can read other tenants' data on the node and escape to it. OpenShift's SCCs normally prevent this, but the namespaces here only have Pod Security *audit/warn* labels, so this is the second lock if someone is granted a stronger SCC. |
| `tenant-pod-security-restricted` | Audit | Reports pods that fall short of the *restricted* profile after SCC admission (non-root, dropped capabilities, seccomp). | Shows which workloads run with more than the strictest profile, typically through an `anyuid` grant, so you can fix them before enforcing. |
| `restrict-node-name` | Enforce | Blocks `spec.nodeName`. | Setting a node name bypasses the scheduler and node taints, which would let a tenant place pods on control-plane nodes. |
| `restrict-control-plane-scheduling` | Enforce | Blocks tolerations for control-plane, master and infra taints, and tolerate-everything tolerations. | Keeps tenant workloads off nodes that run the API server, etcd and platform services, where compromise would affect everyone. |
| `restrict-priority-classes` | Enforce | Blocks `system-*`, `openshift-*` and `kubevirt-*` PriorityClasses. | A high-priority pod can preempt (evict) other tenants' pods and platform components to make room for itself. |
| `restrict-ovn-gateway-annotations` | Enforce | Blocks the OVN-Kubernetes external-gateway pod annotations. | Those annotations can route another namespace's outbound traffic through the pod, bypassing NetworkPolicy and allowing interception. |

## Category: Workload Best Practices

| Policy | Mode | What it does | Why it belongs on a shared cluster |
|---|---|---|---|
| `disallow-latest-tag` | Audit | Reports images with no tag or `:latest`. | A mutable tag means a pod restart can pull different code. On a shared cluster you cannot ask every tenant what is running, so reproducibility has to be visible. |
| `require-requests-limits` | Audit | Reports workloads that do not declare their own CPU/memory requests and memory limit. | The scheduler packs nodes using requests. Workloads relying on tiny namespace defaults get throttled or evicted, and misreport their real needs, which hurts neighbours. |
| `require-probes` | Audit | Reports long-running workloads with a container that has no readiness, liveness or startup probe. | Without probes, traffic reaches pods that are not ready and hung pods are never restarted. In a shared cluster that becomes support load for the platform team. |
| `restrict-image-registries` | Audit | Reports images not from the approved registry list. | Limits supply-chain risk: one tenant pulling an untrusted image runs on shared nodes next to everyone else. |
| `require-ro-rootfs` | Audit | Reports containers without a read-only root filesystem. | Limits what an attacker can do after compromising a container, which matters more when the node is shared. |
| `restrict-pdb-zero-disruption` | Enforce | Blocks PodDisruptionBudgets that allow no disruption (`maxUnavailable: 0`, `minAvailable: 100%`). | Such a budget blocks node drains. One tenant could stall a cluster upgrade or node replacement for everyone. |
| `disallow-default-namespace` | Audit | Reports workloads in the `default` namespace. | `default` carries no tenant label, so none of the guardrails apply there. Workloads landing in it, usually by a forgotten `-n`, escape every control above. |

## Category: Exposure

| Policy | Mode | What it does | Why it belongs on a shared cluster |
|---|---|---|---|
| `restrict-service-exposure` | Enforce | Blocks NodePort and LoadBalancer Services and `externalIPs`. | These bypass the router, open ports on shared nodes, create billable cloud load balancers, and `externalIPs` can intercept traffic meant for other addresses. |
| `restrict-route-ingress-hosts` | Enforce | Route and Ingress hostnames must contain the namespace name; wildcard Routes are blocked. | The router hands a hostname to whoever claims it first, and project admins can set any host. This prevents one tenant squatting on, or impersonating, another's URL. |
| `require-route-tls` | Audit | Reports Routes without TLS or that still allow plain HTTP. | Traffic from users to tenant apps crosses shared infrastructure, so it should be encrypted. |

## Category: RBAC

| Policy | Mode | What it does | Why it belongs on a shared cluster |
|---|---|---|---|
| `restrict-clusteradmin-rolebindings` | Enforce | Blocks RoleBindings to `cluster-admin` in tenant namespaces. | Several policies here exempt anyone holding `cluster-admin`. One namespaced binding could switch those controls off for that identity everywhere. |
| `restrict-cross-tenant-rolebindings` | Enforce | Blocks RoleBindings that grant access to a service account from another tenant's namespace. | Network isolation is pointless if tenant A can hand tenant B's workloads API access to A's secrets and pods. |
| `audit-risky-roles` | Audit | Reports Roles with wildcard verbs or resources, or `bind`/`escalate`/`impersonate`. | These grants are the usual route to privilege escalation. Reporting them gives a review list without blocking legitimate use. |
| `audit-elevated-scc-bindings` | Audit | Reports RoleBindings granting an SCC stronger than `restricted-v2`/`nonroot-v2`. | Each one is a deliberate exception to OpenShift's default security. One place to answer "who runs as root or privileged here?". |

## Category: Resource Management (existing policy)

| Policy | Mode | What it does | Why it belongs on a shared cluster |
|---|---|---|---|
| `generate-vpa-for-workloads` | Generate | Creates a VerticalPodAutoscaler in `Off` mode for each Deployment, StatefulSet and DaemonSet. | Collects sizing recommendations without changing workloads, so quotas and requests can be set from data. Needs the VPA CRD, which was not installed when this was written. |

## Optional (not enabled)

| Policy | Category | What it does | Why you might want it |
|---|---|---|---|
| `tenant-egress-isolation` | Multi-Tenancy | Default-deny egress with allows for DNS, the same tenant, destinations outside the cluster and labelled platform namespaces. | Ingress isolation already keeps tenants apart. Egress control also stops tenant pods reaching platform namespaces that have no NetworkPolicy of their own, and limits what a compromised pod can contact. Off by default because it breaks builds and shared-service calls until those namespaces are labelled. |

---

**Not covered:** these policies assume tenants are separated by namespace only.
They do not give separate nodes, a separate control plane or protection against
a kernel-level container escape. If tenants are mutually untrusted at that
level, a shared cluster is the wrong boundary regardless of policy.
