---
title: OpenShift Virtualization on EC2
parent: Tutorials
nav_order: 6
---

# OpenShift Virtualization on Non-Bare-Metal EC2

**Audience:** Platform / infrastructure engineers running VMs on an AWS cluster that is not bare metal
**Prerequisites:** OpenShift Virtualization operator installed (included in this repo)

---

## Why labels/annotations alone don't work here

OpenShift Virtualization runs VMs via KVM, which needs the host CPU's hardware
virtualization extensions (Intel VT-x / AMD-V), exposed to the guest OS as
`/dev/kvm`. AWS only passes these extensions through on **bare-metal**
instance types (`*.metal`, e.g. `m5.metal`, `c5n.metal`, `i3.metal`). Regular
EC2 instances — including this cluster's `m6a.4xlarge` nodes — do not expose
`/dev/kvm` at all, no matter what labels or annotations you put on the node.
You can confirm this yourself:

```bash
oc debug node/<node-name> -- chroot /host bash -c \
  'ls /dev/kvm 2>&1; egrep -c "(vmx|svm)" /proc/cpuinfo'
```

If `/dev/kvm` is missing and the CPU flag count is `0`, hardware acceleration
is not available on that node — this is a hypervisor-level limitation, not
something OCP or KubeVirt config can work around.

---

## The two real options

### 1. Bare-metal nodes (supported, full performance)

Add a MachineSet targeting a `.metal` instance type (see
[Adding GPU Nodes](adding-gpu-nodes.md) for the general AWS MachineSet
pattern — swap the instance type for a `.metal` one). KVM acceleration works
normally; no emulation config needed. Costs more since AWS bills the whole
physical host.

### 2. Software emulation (unsupported, works on any instance type)

Force KubeVirt to fall back to QEMU software emulation (no hardware
acceleration) via an annotation on the `HyperConverged` CR:

```yaml
metadata:
  annotations:
    kubevirt.kubevirt.io/jsonpatch: '[{"op":"add","path":"/spec/configuration/developerConfiguration","value":{"useEmulation":true}}]'
```

This is what `operators/layer2-operands/values.yaml` (`cnv.hyperConverged.annotations`)
already configures, matching what's live on this cluster. Once HCO reconciles
this, `virt-handler` marks every node schedulable regardless of `/dev/kvm`:

```bash
oc get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.kubevirt\.io/schedulable}{"\n"}{end}'
```

Explicitly **not supported by Red Hat** — CPU-bound work inside VMs runs
10-50x slower than with KVM. Fine for kicking the tires on templates, VM
lifecycle, and networking; not for real workloads.

---

## Verifying VMs run

```bash
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'

oc get vm -A
oc get pods -n openshift-cnv | grep -E 'virt-handler|virt-api|virt-controller'
```

A VM's `virt-launcher` pod log will say
`"Hardware emulation device '/dev/kvm' not present. Using software emulation."`
when running in this mode — that's expected, not an error.

---

## Migrating to bare metal later

Once bare-metal nodes exist, remove the `kubevirt.kubevirt.io/jsonpatch`
annotation from the `HyperConverged` CR and either taint the metal nodes for
VM-only scheduling or use a `nodeSelector`/`nodePlacement` in
`spec.workloads` on the `HyperConverged` CR to target them. Existing VMs need
to be restarted (not just live-migrated) to pick up hardware acceleration.
