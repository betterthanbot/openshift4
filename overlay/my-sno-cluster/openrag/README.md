# OpenRAG Overlay

[OpenRAG](https://github.com/linagora/openrag) (LINAGORA) — RAG over your documents:
upload files, they are parsed, embedded into Milvus, and answered from via an LLM.
Chart: `oci://ghcr.io/linagora/openrag-stack` 0.7.10 (app v2.3.3), rendered into
`bases/openrag/openrag.yaml`.

## What runs (lean profile)

| Component | Where | Notes |
|-----------|-------|-------|
| OpenRAG API + UI | `openrag-openrag` | CPU only. Route `/` |
| Admin UI | `openrag-admin-ui` | Route `/app/` |
| Embedder | vLLM, `Qwen/Qwen3-Embedding-0.6B` | **1 T4 GPU** |
| Reranker | Infinity, `gte-multilingual-reranker-base` | CPU |
| Vector DB | Milvus standalone + MinIO + etcd | |
| SQL | Bitnami PostgreSQL | |
| **Chat LLM** | **external — your RHOAI endpoint** | off until `llm-endpoint-patch.yaml` is enabled |

Turned off vs. upstream defaults: Whisper (audio transcription), VLM (image
captioning), in-chart LLM, Ray/KubeRay, bundled Prometheus/Grafana. The upstream
defaults need ~5 GPUs and ReadWriteMany storage; see the header of
`bases/openrag/values.yaml`.

## 1. Create the Secrets (once, before the first sync)

Nothing sensitive is in git. The chart reads two Secrets that must exist first:

```bash
oc new-project openrag 2>/dev/null || true

oc create secret generic openrag-env-secrets -n openrag \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 16)" \
  --from-literal=AUTH_TOKEN="$(openssl rand -hex 24)" \
  --from-literal=METRICS_TOKEN="$(openssl rand -hex 24)" \
  --from-literal=API_KEY="<token for your LLM endpoint, e.g. a MaaS token>" \
  --from-literal=EMBEDDER_API_KEY=EMPTY \
  --from-literal=VLM_API_KEY=EMPTY \
  --from-literal=TRANSCRIBER_API_KEY=EMPTY \
  --from-literal=RERANKER_API_KEY=EMPTY \
  --from-literal=HF_TOKEN="<huggingface token, or EMPTY for public models>"

oc create secret generic openrag-minio-credentials -n openrag \
  --from-literal=accesskey=openrag \
  --from-literal=secretkey="$(openssl rand -hex 24)"
```

`AUTH_TOKEN` is the admin API key for OpenRAG itself — keep it to log in.

## 2. Point it at your RHOAI model

1. Edit `llm-endpoint-patch.yaml` — `BASE_URL` (ending in `/v1/`) and `MODEL`.
   It ships with the MaaS Qwen2.5-1.5B example.
2. Make sure `API_KEY` in `openrag-env-secrets` is a valid token for that endpoint
   (`oc edit secret openrag-env-secrets -n openrag`, then restart `openrag-openrag`).
3. Uncomment the `patches:` block in `kustomization.yaml` and push.

Without this, the stack deploys and ingests documents, but chat has no LLM.

GPU budget: the embedder takes one T4. The MaaS example model uses the
`t4-g4dn2xlarge` hardware profile, i.e. the other one.

## Updating the chart

```bash
cd bases/openrag
# bump OPENRAG_VERSION in Makefile, then:
make            # helm pull into vendor/ (gitignored) + helm template -> openrag.yaml
```

Commit `openrag.yaml`. Base-level OpenShift fixes (Recreate strategy for RWO
volumes, reranker cache) are kustomize patches in `bases/openrag/kustomization.yaml`,
so they survive re-rendering.

## Cluster domain

The Routes pin `openrag.apps.<cluster-domain>` in `route.yaml` (and the MaaS URL in
`llm-endpoint-patch.yaml`). Update both when the cluster changes.
