# RHOAI & Cluster Monitoring Dashboards

A suite of 9 production-ready Grafana dashboards for Red Hat OpenShift and RHOAI environments, organized around who's actually looking at them: cluster/platform admins, AI platform admins, MaaS admins/analysts, and non-technical stakeholders.

All dashboards are provisioned automatically via the Grafana Operator using ConfigMaps in [../generated/](../generated/). Run `make` in [../](../) to regenerate ConfigMaps after editing JSON files here.

---

## Dashboards

| # | Dashboard | UID | Refresh | Time Range | Persona | Key Metrics |
|---|-----------|-----|---------|------------|---------|-------------|
| 1 | [Admin: Cluster Health](#1-admin-cluster-health) | `d192c7df-...` | 10s | 6h | Cluster admin | Nodes, GPU (DCGM), pods, OOMKill, CrashLoop, capacity budget, ingress, disk pressure |
| 2 | [Admin: API & Network Analysis](#2-admin-api--network-analysis) | `net-status-adv` | 5s | 1h | Cluster admin | HTTP status codes, latency, network I/O |
| 3 | [Admin: VPA Optimization & Health](#3-admin-vpa-optimization--health) | `vpa-comprehensive` | — | 6h | Cluster admin | VPA recommendations vs actual provisioning |
| 4 | [ACM: Right-Sizing Namespace](#4-acm-right-sizing-namespace) | `bnqQIPySE` | — | 7d | Cluster admin | ACM right-sizing CPU/memory per namespace |
| 5 | [Platform: GitOps & Multi-Tenancy Health](#5-platform-gitops--multi-tenancy-health) | `platform-gitops-multitenancy` | 1m | 6h | Cluster admin | ArgoCD app sync/health, tenant ResourceQuota utilization, HPA status |
| 6 | [AI Platform Admin: Overview](#6-ai-platform-admin-overview) | `ai-platform-admin-overview` | 1m | 6h | AI platform admin | Deployed models, GPU inventory/utilization, per-project resource use, gateway/control-plane health |
| 7 | [AI Platform Admin: Model Performance](#7-ai-platform-admin-model-performance) | `ai-platform-admin-model-performance` | 10s | 1h | AI platform admin | TTFT/TPOT/E2E latency (P50/95/99), throughput, queue depth, KV cache, GPU correlation |
| 8 | [AI MaaS Admin & Analyst: Usage & Rate Limits](#8-ai-maas-admin--analyst-usage--rate-limits) | `ai-maas-admin-analyst-usage` | 1m | 24h | MaaS admin / analyst | Requests/tokens by user & group, rejection rate, active users over time, rate/token limits vs actual, cost-center breakdown |
| 9 | [MaaS Stakeholder Summary](#9-maas-stakeholder-summary) | `maas-stakeholder-summary` | 5m | 7d | Stakeholder / exec | Active users, total requests/tokens, success rate, adoption by team/model/cost-center |

---

## 2026-07-26: Consolidation & Persona Rebuild

The dashboard folder had grown to 19 dashboards across several sessions with heavy, undocumented overlap — 8 dashboards independently slicing the same Kuadrant/Limitador request-accounting data, and 4 more repeating the same TTFT/TPOT/KV-cache/GPU vLLM panels at slightly different scopes. This pass cut that down to the 9 above, organized around personas instead of ad-hoc topics.

**What triggered it:** the cluster's metrics catalog (`../../../metrics`, refreshed 2026-07-26) confirmed `authorized_calls`, `authorized_hits`, and `limited_calls` are now live with real data — as of the 2026-07-24 audit below, these had **zero active series**. Verified live against Thanos:

- `authorized_calls` labels: `user, subscription, limitador_namespace, cost_center, organization_id` — **no `limit_name`**. The old "RHOAI MaaS Group Monitoring" dashboard's `authorized_calls{limit_name=~"$limit_name"}` filter was a real bug (silently matched nothing), not just metric staleness. Fixed by grouping on `subscription` instead everywhere in the new dashboard 8.
- `authorized_hits` labels: adds `model` — this is the per-request token-count metric.
- `limited_calls` labels: adds `limit_name` (both `*-tier-requests` and `*-tokens` limit names exist, though only `*-tokens` has ever actually fired on this cluster).
- `user` label values confirmed real (`user1`, `user3` seen live) — resolves the "unverified caveat" that blocked per-user usage in the old dashboard 12.
- `cost_center` / `organization_id` are present and were unused by any prior dashboard — now powering the cost-center breakdown in dashboards 8 and 9.

**Deleted (15 files, all content merged or dead):**
| File | Disposition |
|---|---|
| `Admin OCP Cluster Overview.json` | unique panels (capacity budget, ingress-by-status, disk pressure) merged into dashboard 1 |
| `RHOAI GPU Utilization & Consumption.json` | merged into dashboard 6 |
| `RHOAI Inference Endpoint Monitoring.json` | merged into dashboard 7 |
| `RHOAI vLLM & GPU Master Dashboard.json` | merged into dashboard 7 |
| `RHOAI vLLM Performance Monitor.json` | merged into dashboard 7 |
| `vLLM Advanced Performance Dashboard.json` | merged into dashboard 7 |
| `RHOAI MaaS Cluster Overview.json` | merged into dashboard 6 |
| `RHOAI MaaS Model Serving.json` | merged into dashboard 6 |
| `RHOAI MaaS Kuadrant Gateway Health.json` | merged into dashboard 6 |
| `RHOAI MaaS Group Monitoring.json` | strict subset of "(Detailed)"; merged into dashboard 8 |
| `RHOAI MaaS Group Monitoring (Detailed).json` | merged into dashboard 8 |
| `RHOAI MaaS Usage Overview.json` | merged into dashboard 8 |
| `RHOAI MaaS Per-User Token Usage.json` | merged into dashboard 8 (the `user`-label caveat is now resolved) |
| `RHOAI MaaS User & API Key Drilldown.json` | obsolete — existed *because* `user` wasn't a Prometheus label; now that it is, the blocked Loki/log-based approach (tagged `not-yet-wired`) isn't needed |
| `RHOAI MaaS Dashboard.json` | legacy v2 schema, already documented as superseded |

**Note on "Admin" vs "Analyst":** the ask was for both an "AI MaaS Admin" and an "Analyst" persona, but Kuadrant/Limitador usage data doesn't actually differ by role — both would look at the same requests/tokens/rejections/limits. Built as one combined dashboard (8) instead of two near-duplicates, to avoid recreating the exact overlap problem this pass fixes. Split it if the two audiences turn out to need materially different views in practice.

---

## Metrics Verification (2026-07-24)

Every dashboard in this folder was audited against a fresh curl of this cluster's live metrics catalog ([../../../metrics](../../../metrics), 4253 metric names at the time). Where a query referenced a metric name that isn't in that catalog, it was either fixed (renamed to the current real metric) or clearly flagged as environment-dependent rather than a bug. Findings (dashboard numbers below refer to the pre-2026-07-26 numbering; see the table above for where that content lives now):

**Renamed on this vLLM version:**
| Old name (no longer exists) | Current name |
|---|---|
| `vllm:time_per_output_token_seconds_bucket` | `vllm:inter_token_latency_seconds_bucket` |
| `vllm:gpu_prefix_cache_hits_total` / `..._queries_total` | `vllm:prefix_cache_hits_total` / `..._queries_total` |
| `vllm:gpu_cache_usage_perc` + `vllm:cpu_cache_usage_perc` | `vllm:kv_cache_usage_perc` (unified - CPU swap offload no longer exists in the V1 engine, so the CPU series was dropped rather than left dangling) |
| `vllm:request_prefix_cache_hits` / `..._misses` | `vllm:prefix_cache_hits_total` / `..._queries_total` (hit rate = hits / queries) |
| `haproxy_backend_sessions_total` | `haproxy_backend_connections_total` |

**Confirmed present, contrary to an earlier `techdebt.md` finding** that these recording rules didn't exist anywhere on the cluster: `kserve_vllm:*` and `accelerator_gpu_utilization` are both in the live catalog.

**Confirmed absent as of 2026-07-24 (later resolved — see the 2026-07-26 section above):**
- `authorized_calls`, `limited_calls`, `authorized_hits` (Limitador request counters) — now live with real data.

**Still confirmed absent cluster-wide as of 2026-07-26 (not a dashboard bug — genuinely no active series):**
| Missing | Affects | What still works instead |
|---|---|---|
| `kube_customresource_verticalpodautoscaler_*` (all of them) | Dashboard 3 (VPA) | Nothing - VPA CRD-state isn't installed/exposed at all right now. Queries are correct for when it is; dashboard description says so explicitly. |
| `acm_rs:*` (all of them) | Dashboard 4 (ACM) | Nothing - needs an ACM hub relationship this standalone SNO cluster doesn't have. Dashboard description says so explicitly. |

**Also fixed:** a dead `or nginx_ingress_controller_requests` fallback clause (that metric never existed here) and a hardcoded literal `65592` masquerading as a query in a "GPU Memory Blocks" gauge (replaced with a real `vllm:kv_cache_usage_perc` query) — both in dashboards later merged into dashboard 7.

---

## Prerequisites by Dashboard

| Requirement | Dashboards |
|---|---|
| `kube-state-metrics` | 1, 3, 5 |
| `node-exporter` | 1 |
| OpenShift HAProxy metrics (`haproxy_*`) | 1, 7 |
| NVIDIA GPU Operator / DCGM Exporter | 1, 6, 7 |
| VPA deployed + kube-state-metrics CRD support | 3 |
| Red Hat ACM with right-sizing enabled | 4 |
| ArgoCD metrics exporter (`argocd_*`) | 5 |
| kube-state-metrics ResourceQuota/HPA collectors (`kube_resourcequota`, `kube_horizontalpodautoscaler_*`) | 5 |
| vLLM runtime exposing Prometheus metrics (`vllm:*`) | 6, 7 |
| Kuadrant control-plane metrics (`kuadrant_*`) | 6 |
| Kuadrant/Limitador with `exhaustive` telemetry (`authorized_calls`/`authorized_hits`/`limited_calls` with `user`/`subscription`/`cost_center`/`organization_id` labels) | 8, 9 |

---

## Datasource

All dashboards use a `DS_PROMETHEUS` template variable (type: datasource) so the datasource UID resolves dynamically — required for the Grafana Operator where UIDs are assigned at deploy time.

**Exception:** The ACM Right-Sizing dashboard uses a variable named `datasource` (legacy). If you import it manually it will prompt for the datasource; it works correctly but the variable name differs from the other dashboards.

---

## 1. Admin: Cluster Health

"Single Pane of Glass" for overall cluster health — infrastructure (nodes, GPU, network) through to workload stability (pods, OOMKills, CrashLoops), plus the capacity-budget, ingress-by-status-code, and disk-pressure panels absorbed from the now-deleted "Admin: OCP Cluster Overview".

**Variables:** `DS_PROMETHEUS`, `namespace`

Rows: Cluster Health Overview, Node-Level Breakdown, GPU Monitoring (DCGM), Network I/O, Workload Summary, Critical Events & Errors, Capacity Budget (CPU/Memory/GPU allocatable vs requested), Ingress & Storage Pressure.

**Tags:** `kubernetes`, `openshift`, `gpu`, `nvidia`, `cluster`

---

## 2. Admin: API & Network Analysis

High-level view of HTTP API health, status code distribution, and cluster network traffic. Useful for quickly spotting ingress degradation or network saturation.

**Tags:** `network`, `http`, `status-codes`, `detailed`

---

## 3. Admin: VPA Optimization & Health

Tracks VPA adoption, recommendation trends, and compares VPA targets against actual pod limits/requests for data-driven right-sizing.

**Variables:** `DS_PROMETHEUS`, `namespace`, `vpa`

**Tags:** `vpa`, `autoscaling`, `kubernetes`

---

## 4. ACM: Right-Sizing Namespace

Uses ACM right-sizing recording rules (`acm_rs:*`) to identify over-provisioned namespaces across the fleet.

**Variables:** `datasource`, `cluster`, `profile`, `days`

> **Note:** Requires Red Hat ACM with the right-sizing feature and ACM Observability (Thanos). Will not work without ACM.

**Tags:** `ACM`, `Right-Sizing`

---

## 5. Platform: GitOps & Multi-Tenancy Health

Is the GitOps pipeline that manages this entire platform actually healthy, and are the tenant namespaces it deploys workloads into anywhere near their resource limits.

**Variables:** `DS_PROMETHEUS`

**Tags:** `maas`, `platform`, `gitops`, `argocd`, `multi-tenancy`

---

## 6. AI Platform Admin: Overview

Fleet-level technical health for AI platform admins: what's deployed, GPU inventory/utilization, per-project resource consumption, and gateway/control-plane health. Replaces "RHOAI MaaS Cluster Overview", "RHOAI MaaS Model Serving", "RHOAI MaaS Kuadrant Gateway Health", and "RHOAI GPU Utilization & Consumption".

**Variables:** `DS_PROMETHEUS`, `namespace`, `model_name`

### Rows

- **Fleet KPIs** — system health %, deployed models count, GPU utilization, request success rate, gateway ready.
- **Model Deployments** — one table row per (model, namespace): active signal, requests, P90 E2E latency, error rate, GPU util, CPU util.
- **GPU Inventory & Utilization** — total NVIDIA PCI devices, GPUs reporting DCGM, per-device utilization/power.
- **Project Resource Usage** — GPU/CPU/memory utilization by namespace, stacked.
- **Gateway & Control-Plane Health** — `kuadrant_ready`, policies enforced/total, allow/deny/error rate, per-gateway-pod breakdown.

**Prerequisites:** vLLM PodMonitors exposing `vllm:*` with `model_name`/`namespace`/`pod` labels, NVIDIA GPU Operator/DCGM, Kuadrant operator metrics.

**Tags:** `ai-platform-admin`, `rhoai`, `maas`, `gpu`, `kuadrant`

---

## 7. AI Platform Admin: Model Performance

Deep-dive vLLM/model-serving performance: ingress-to-engine traffic correlation, latency (TTFT/TPOT/E2E at P50/95/99), throughput and queue saturation, KV cache efficiency, and GPU/pod resource correlation. Replaces "RHOAI Inference Endpoint Monitoring", "RHOAI vLLM & GPU Master Dashboard", "RHOAI vLLM Performance Monitor", and "vLLM Advanced Performance Dashboard" — four dashboards that had converged on repeating the same panels at slightly different namespace/pod scopes.

**Variables:** `DS_PROMETHEUS`, `namespace`, `pod` (multi), `model` (multi), `interval`

### Rows

Executive KPIs → Traffic Flow (ingress↔vLLM↔KServe correlation, error rates, request outcomes) → Latency Deep Dive (TTFT/TPOT/E2E, P50/95/99) → Throughput & Queue → KV Cache (usage %, prefix hit rate, per-pod) → GPU Correlation → Pod System Resources.

**Prerequisites:** OpenShift Router (HAProxy) metrics, vLLM Prometheus metrics, KServe wrapper metrics (`kserve_http_*`), DCGM Exporter, cAdvisor/kubelet.

**Tags:** `ai-platform-admin`, `vllm`, `rhoai`, `gpu`, `performance`

---

## 8. AI MaaS Admin & Analyst: Usage & Rate Limits

Who's using MaaS, how much, and how close to their limits — for MaaS admins and analysts. Replaces "RHOAI MaaS Group Monitoring", "RHOAI MaaS Group Monitoring (Detailed)", "RHOAI MaaS Usage Overview", and "RHOAI MaaS Per-User Token Usage".

**Variables:** `DS_PROMETHEUS`, `user` (multi), `subscription` (multi)

### Rows

- **Overview** — total requests, total tokens, rejected requests, rejection rate %, active users.
- **Active Users Over Time** — distinct users in a trailing 1h window, graphed across the selected range (the "how many users throughout the day/week" view).
- **Requests & Rejections by Group** — authorized/rejected requests per minute by subscription, plus token-limit hits by group+model.
- **Token Usage by User** — table of tokens/requests/rejected per (user, subscription, model).
- **Rate Limits & Token Limits** — live usage gauged against the configured per-tier limits (team-alpha: 5 req/min, 10k tokens/min per model; team-bravo: 30 req/min, 10k tokens/min per model — see `dumps/rhcl-ratelimitpolicy-*.yaml` / `dumps/rhcl-tokenratelimitpolicy-*.yaml` for the source of truth; Limitador itself doesn't expose configured thresholds as a metric).
- **KV Cache by Model** — capacity-planning signal, not just a platform-ops one.
- **Cost Center & Organization Breakdown** — requests/tokens by `cost_center`/`organization_id`.

**Prerequisites:** Kuadrant/Limitador with `exhaustive` telemetry, `user`/`subscription`/`cost_center`/`organization_id` labels on `authorized_calls`/`authorized_hits`/`limited_calls` (confirmed live 2026-07-26).

**Note:** `authorized_calls` has **no** `limit_name` label in this Limitador build (only `limited_calls` does) — group breakdowns here use `subscription` instead, fixing a filter that silently matched nothing in the dashboard this replaces.

**Tags:** `maas`, `usage`, `kuadrant`, `analyst`, `admin`

---

## 9. MaaS Stakeholder Summary

Executive-level snapshot of MaaS adoption and health — no filters, a handful of big numbers, meant to be glanceable. New dashboard, not a port of anything.

**Variables:** `DS_PROMETHEUS` only (no filters — fixed exec view)

Rows: MaaS at a Glance (active users, total requests, total tokens, success rate — 7d), Adoption Over Time (active users per day), Usage Breakdown (by team / cost center / model), Platform Health (node readiness, gateway ready).

For per-user, per-limit, or per-model detail, see dashboard 8.

**Tags:** `maas`, `stakeholder`, `executive`
