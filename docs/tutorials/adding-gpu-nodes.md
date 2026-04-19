---
title: Adding GPU Nodes
parent: Tutorials
nav_order: 5
---

# Adding GPU Nodes on AWS

**Audience:** Platform / infrastructure engineers scaling the cluster with GPU capacity
**Prerequisites:** AWS cluster with Machine API enabled, NVIDIA GPU Operator installed (included in this repo)

---

## Overview

GPU workloads (model serving, AI/ML training) require nodes backed by GPU instances. On AWS, you provision GPU nodes by creating a `MachineSet` that targets a GPU instance type such as `g4dn.2xlarge` (1× NVIDIA T4). The NVIDIA GPU Operator (already deployed by this repo) automatically installs the driver and device plugin on any node labelled with GPU capacity.

---

## Step 1 — Find your cluster infrastructure values

Several fields in the MachineSet are cluster-specific. Retrieve them before filling in the template:

```bash
# Cluster infrastructure name (used throughout the MachineSet)
oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}'

# Available availability zones and existing subnet names
oc get machineset -n openshift-machine-api -o yaml | grep availabilityZone | sort -u
oc get machineset -n openshift-machine-api -o yaml | grep 'tag:Name' -A1 | grep subnet | sort -u

# AMI ID used by existing worker nodes (reuse the same AMI)
oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.ami.id}'

# IAM instance profile name
oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.iamInstanceProfile.id}'

# Security group tag names
oc get machineset -n openshift-machine-api -o jsonpath='{.items[0].spec.template.spec.providerSpec.value.securityGroups}'
```

---

## Step 2 — Apply the MachineSet

Replace all `<placeholder>` values with the outputs from Step 1, then apply:

```yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  annotations:
    capacity.cluster-autoscaler.kubernetes.io/labels: kubernetes.io/arch=amd64
    machine.openshift.io/GPU: '1'
    machine.openshift.io/memoryMb: '32768'
    machine.openshift.io/vCPU: '8'
  name: <cluster-id>-worker-gpu-<az>
  namespace: openshift-machine-api
  labels:
    machine.openshift.io/cluster-api-cluster: <cluster-id>
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: <cluster-id>
      machine.openshift.io/cluster-api-machineset: <cluster-id>-worker-gpu-<az>
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: <cluster-id>
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: <cluster-id>-worker-gpu-<az>
    spec:
      lifecycleHooks: {}
      metadata: {}
      providerSpec:
        value:
          apiVersion: machine.openshift.io/v1beta1
          kind: AWSMachineProviderConfig
          credentialsSecret:
            name: aws-cloud-credentials
          userDataSecret:
            name: worker-user-data
          placement:
            region: <region>
            availabilityZone: <az>
          instanceType: g4dn.2xlarge
          ami:
            id: <ami-id>
          iamInstanceProfile:
            id: <cluster-id>-worker-profile
          blockDevices:
            - ebs:
                encrypted: true
                iops: 0
                kmsKey:
                  arn: ''
                volumeSize: 100
                volumeType: gp2
          securityGroups:
            - filters:
                - name: 'tag:Name'
                  values:
                    - <cluster-id>-node
            - filters:
                - name: 'tag:Name'
                  values:
                    - <cluster-id>-lb
          subnet:
            filters:
              - name: 'tag:Name'
                values:
                  - <cluster-id>-subnet-private-<az>
          tags:
            - name: kubernetes.io/cluster/<cluster-id>
              value: owned
          metadataServiceOptions: {}
          deviceIndex: 0
```

Apply it:

```bash
oc apply -f machineset-gpu.yaml
```

---

## GPU Instance Types (AWS)

| Instance | GPU | VRAM | vCPU | RAM | Use case |
|----------|-----|------|------|-----|----------|
| `g4dn.xlarge` | 1× T4 | 16 GB | 4 | 16 GB | Light inference |
| `g4dn.2xlarge` | 1× T4 | 16 GB | 8 | 32 GB | Standard inference / dev |
| `g4dn.12xlarge` | 4× T4 | 64 GB | 48 | 192 GB | Multi-GPU inference |
| `g5.2xlarge` | 1× A10G | 24 GB | 8 | 32 GB | LLM inference |
| `p3.2xlarge` | 1× V100 | 16 GB | 8 | 61 GB | Training |

---

## Step 3 — Verify the node is ready

```bash
# Watch the machine provision (takes ~5 minutes)
oc get machines -n openshift-machine-api -w

# Once Running, confirm the node joined
oc get nodes -l machine.openshift.io/cluster-api-machine-type=worker

# Confirm the GPU is detected by the device plugin
oc describe node <gpu-node-name> | grep -A5 "nvidia.com/gpu"
```

You should see `nvidia.com/gpu: 1` in the node's allocatable resources.

---

## Step 4 — Confirm GPU Operator is healthy

```bash
oc get pods -n nvidia-gpu-operator
```

All pods should be `Running`. Key components:

| Pod | Purpose |
|-----|---------|
| `nvidia-driver-daemonset-*` | Installs the NVIDIA kernel driver |
| `nvidia-device-plugin-daemonset-*` | Exposes GPU as a schedulable resource |
| `nvidia-dcgm-exporter-*` | Exports GPU metrics to Prometheus |
| `gpu-feature-discovery-*` | Labels nodes with GPU capabilities via NFD |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| Machine stuck `Provisioning` | Wrong AMI ID or subnet | Verify values from Step 1 |
| Node joins but `nvidia.com/gpu` absent | GPU Operator not ready | Check `nvidia-driver-daemonset` pod logs |
| Driver pod `CrashLoopBackOff` | Kernel version mismatch | Check GPU Operator logs; may need to pin driver version in `ClusterPolicy` |
| NFD not labelling GPU node | NFD worker not running on new node | Check `node-feature-discovery-worker` daemonset |

---

## Notes

- **Do not commit MachineSet YAMLs with cluster-specific IDs to this repo** — they are not portable across clusters.
- Start with `replicas: 1` and scale up after validating the node is healthy.
- GPU nodes are expensive — consider setting `replicas: 0` when not in use and scaling up on demand, or use the cluster autoscaler.
