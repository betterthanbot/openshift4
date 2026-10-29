# OpenRAG Overlay

[OpenRAG](https://github.com/langflow-ai/openrag) (langflow-ai) — an agentic RAG platform:
upload documents, they are parsed (Docling), embedded into OpenSearch, and answered from by an
LLM through a Langflow-built agent. Upstream chart `kubernetes/helm/openrag` at **v0.8.0**
(images `0.8.0`), rendered into `bases/openrag/openrag.yaml`.

> This replaced an earlier deployment of the unrelated LINAGORA `openrag-stack` chart.

## What runs

| Component | Where | Notes |
|-----------|-------|-------|
| UI + API | `openrag-frontend` (3000) → `openrag-backend` (8000) | Route `openrag.apps.<domain>` |
| Langflow | `openrag-langflow` (7860) | SQLite on its own PVC; flows pinned to the v0.8.0 commit |
| OpenSearch | `openrag-opensearch` StatefulSet | project image; **not in the chart** → `bases/openrag/opensearch.yaml` |
| docling-serve | `docling-serve` (5001) | CPU; **not in the chart** → `bases/openrag/docling.yaml` |
| Embeddings | `openrag-embedder` — vLLM, Qwen3-Embedding-0.6B | **1 T4**; `embedder.yaml` |
| Chat LLM | your MaaS model `maas-demo/qwen25-15b-instruct` | via the RHOAI provider, see below |

## 1. First deploy (in this order)

Nothing sensitive is in git. Four Secrets are created by hand; the pods stay in
`CreateContainerConfigError` until they exist.

```bash
# a) generates passwords and creates openrag-dotenv, openrag-langflow-dotenv, openrag-opensearch
#    (creates the namespace if needed; refuses to run twice). Needs helm, git, openssl, oc.
make -C bases/openrag secrets

# b) the MaaS key the backend uses for chat. Mint one as a maas-team-a member (e.g. platform-admin):
#    POST https://maas.apps.<domain>/maas-api/v1/api-keys  {"name":"openrag"}
read -rs KEY
oc create secret generic openrag-rhoai -n openrag --from-literal=api-key="$KEY"; unset KEY
```

Then push and sync — the `openrag` Application has **no auto-sync**:

```bash
oc annotate application openrag -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite
oc patch application openrag -n openshift-gitops --type merge -p '{"operation":{"sync":{}}}'
```

## 2. Chat LLM → RHOAI

The backend runs OpenRAG's `rhoai` provider (`backend-rhoai-patch.yaml`): chat goes to the MaaS
gateway, embeddings to the in-namespace embedder. The provider is hidden by default, so
`model-providers.yaml` enables it (`OPENRAG_MODEL_PROVIDERS_CONFIG`, not hot-reloaded).

- **Tool calling is required.** OpenRAG's agent drives the model with tool calls; without
  `--enable-auto-tool-choice` and a `--tool-call-parser` vLLM answers every one with a 400.
  The model's `VLLM_ADDITIONAL_ARGS` must include
  `--enable-auto-tool-choice --tool-call-parser=hermes` (hermes is Qwen2.5's parser).
  **Already applied live** to `maas-demo/qwen25-15b-instruct` (it is not managed from this repo) and
  verified: a tool request went from HTTP 400 to `finish_reason: tool_calls`. If you recreate the
  model, re-add the flags.
- **Changing that model's spec deadlocks the rollout.** Its `models` volume is ReadWriteOnce, so the
  replacement pod can't attach it while the old pod (which only leaves once the new one is Ready)
  holds it, and both T4s are taken. Finish it by scaling the old ReplicaSet to 0
  (`oc scale rs <old-rs> -n maas-demo --replicas=0`): a few minutes of model downtime.
- **Seeded once.** `LLM_PROVIDER`, `RHOAI_*` etc. are read only on the backend's first boot; after that
  the stored config wins. Change provider/model afterwards in the UI's Settings, not here.
- **Limits of this model.** Qwen2.5-1.5B with `--max-model-len=8192`, and the `team-a-sub`
  subscription caps it at 8192 tokens/min — tight for an agent with tool definitions + retrieved chunks.

## 3. Security

With no auth provider configured OpenRAG is in **no-auth mode: every visitor is an admin** (uploads,
settings, and your MaaS key). Configure Google/Microsoft OAuth, or restrict the Route with the
`haproxy.router.openshift.io/ip_whitelist` annotation shown in `route.yaml`.

## Troubleshooting

- **Backend logs `Attempt to generate Langflow API key failed` (400, then 429), Langflow logs
  `Fernet key must be 32 url-safe base64-encoded bytes`.** `LANGFLOW_SECRET_KEY` isn't a valid Fernet
  key (Langflow uses any value >= 32 chars verbatim as one). `make secrets` now generates a valid
  one; on an install made earlier run `make -C bases/openrag rotate-langflow-key` (rewrites the value
  in both `.env` Secrets, restarts langflow + backend; the admin password and database are untouched).
- **Backend log loops on `OpenSearch healthy but cluster has not reached expected node count` and the
  pod is killed (exit 137).** The backend assumes a multi-node OpenSearch unless
  `OPENSEARCH_NODE_COUNT_CHECK_ENABLED=false`; the base patches that in for the single node.
- **Embedder: `LocalEntryNotFoundError ... outgoing traffic has been disabled`.** The Red Hat vLLM
  image ships with Hugging Face offline mode on; `embedder.yaml` sets `HF_HUB_OFFLINE=0`.
- **Backend init: `image has non-numeric user (curl_user)`.** The chart's init containers set no
  numeric user; the base patches in UID 1000.

## Known caveats

- **MaaS gateway** intermittently returns an empty 200 body for non-streaming requests. Chat is mostly
  streaming and tolerates it; embeddings are not, hence the direct embedder.
- **maas-db has no storage**: if that Postgres restarts, the MaaS key is lost (restart `maas-api` to
  re-create its schema, mint a new key, update `openrag-rhoai`, restart the backend).
- **Shared RWO volume**: backend and langflow share `openrag-shared`; the base pins the backend to
  langflow's node (podAffinity). Upstream wants ReadWriteMany, which this cluster doesn't have.
- **OpenSearch** relies on single-node discovery to skip bootstrap checks (`vm.max_map_count` is the
  RHCOS default). If large indices fail with "Map failed", raise it with a Tuned/MachineConfig.
- The embedder downloads the model from Hugging Face on first start (egress needed) into its PVC.

## Updating

```bash
cd bases/openrag
# bump OPENRAG_REF in the Makefile, global.imageTag + hashes in values.yaml, the OpenSearch image
# tag in opensearch.yaml and (if wanted) docling's tag in docling.yaml, then:
make
```

Commit `openrag.yaml`, never `vendor/`. `make` strips the chart's generated Secrets and an unused
IBM-Cloud StorageClass (`filter-render.py`).

## Cluster domain

The Route host in `route.yaml` and the MaaS URL in `backend-rhoai-patch.yaml` pin
`apps.cluster-68qgz.68qgz.sandbox2261.opentlc.com`. Update both when the cluster changes.
