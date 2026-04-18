---
title: LokiStack S3 Setup
parent: Tutorials
nav_order: 4
---

# LokiStack S3 Storage Setup

LokiStack requires an S3-compatible object storage bucket to store logs. A placeholder Secret is committed to this repo — you must fill in your real credentials before LokiStack will start.

ArgoCD creates the secret on first sync but **never overwrites it**, so your credentials are safe after you enter them.

---

## Prerequisites

- An S3-compatible bucket (AWS S3, Minio, ODF, etc.)
- Access key ID and secret access key with read/write permissions to the bucket
- The bucket must already exist — LokiStack does not create it

---

## Option 1 — OpenShift Web Console (no CLI required)

1. Open the OpenShift Web Console and log in as a cluster admin.
2. Navigate to **Workloads → Secrets** (switch to the `openshift-logging` namespace using the namespace dropdown at the top).
3. Find the secret named **`logging-loki-s3`** and click on it.
4. Click **Actions → Edit Secret**.
5. Replace each placeholder value with your real credentials:

   | Key | Value |
   |-----|-------|
   | `access_key_id` | Your S3 access key ID |
   | `access_key_secret` | Your S3 secret access key |
   | `bucketnames` | The name of your S3 bucket |
   | `endpoint` | Your S3 endpoint URL (e.g. `https://s3.ap-southeast-1.amazonaws.com`) |
   | `region` | Your S3 region (e.g. `ap-southeast-1`) |

6. Click **Save**.

ArgoCD will detect the secret exists and leave the data untouched on future syncs.

---

## Option 2 — CLI (`oc`)

Replace the placeholder values in a single command:

```bash
oc create secret generic logging-loki-s3 \
  -n openshift-logging \
  --from-literal=access_key_id=<your-access-key-id> \
  --from-literal=access_key_secret=<your-secret-access-key> \
  --from-literal=bucketnames=<your-bucket-name> \
  --from-literal=endpoint=https://s3.ap-southeast-1.amazonaws.com \
  --from-literal=region=ap-southeast-1 \
  --dry-run=client -o yaml | oc apply -f -
```

> The `--dry-run=client -o yaml | oc apply -f -` pattern safely overwrites the placeholder secret with your real values without needing to delete it first.

---

## Verify LokiStack starts

After saving the secret, trigger an ArgoCD sync on `operators-layer2`, then check:

```bash
# LokiStack should move to Ready
oc get lokistack logging-loki -n openshift-logging

# Pods should be Running
oc get pods -n openshift-logging -l app.kubernetes.io/name=loki
```

If pods are crash-looping, check the logs:

```bash
oc logs -n openshift-logging -l app.kubernetes.io/name=loki --tail=50
```

Common issues:

| Symptom | Likely cause |
|---------|-------------|
| `AccessDenied` in logs | Access key lacks permissions on the bucket |
| `NoSuchBucket` in logs | Bucket name is wrong or bucket does not exist |
| `InvalidEndpoint` | Endpoint URL is malformed or wrong region |
| LokiStack stuck `Pending` | Secret data still contains placeholder `<...>` values |

---

## Updating credentials later

If you rotate your S3 keys, edit the secret again using either method above. LokiStack will pick up the new credentials within a few minutes without restarting pods.
