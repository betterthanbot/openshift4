# Gatus Overlay

## Updating the Cluster FQDN

All cluster-specific endpoints are defined in `gatus-config-patch.yaml`. The cluster domain appears as:

```
apps.cluster.example.com
```

When your cluster FQDN changes, run a single find-and-replace:

```bash
sed -i 's/apps.cluster.example.com/apps.<NEW-CLUSTER-DOMAIN>/g' \
  overlay/my-sno-cluster/gatus/gatus-config-patch.yaml
```

Then commit and push — ArgoCD will sync the updated config automatically.

## Adding or Removing Endpoints

Edit `gatus-config-patch.yaml` and add/remove entries under the appropriate group in the `endpoints:` list.

Endpoint groups:
- **Platform Endpoints** — OpenShift core routes (console, OAuth, GitOps, etc.)
- **Route Endpoints** — Demo/workload apps running on the cluster
- **Logging** — Loki and log aggregation routes
- **Monitoring** — Prometheus, Alertmanager, Thanos
- **Security** — StackRox/ACS
- **External Cluster** — Other OCP clusters to monitor
- **Image Repositories** — Docker Hub, Quay, Red Hat registries
- **LLM Endpoints** — OpenAI, Anthropic, Google Gemini APIs

## How It Works

`gatus-config-patch.yaml` is a Kustomize strategic merge patch that replaces the `data` field of the `gatus-config` ConfigMap defined in `bases/gatus/gatus.yaml`. ArgoCD applies it on sync but will not overwrite it if the config is updated at runtime by the Gatus discovery CronJob (controlled by `ignoreDifferences` in `argocd/appset-workloads.yaml`).
