# RHOAI & Cluster Monitoring Dashboards

A suite of 9 production-ready Grafana dashboards for Red Hat OpenShift and RHOAI environments. Covers cluster infrastructure, API traffic, VPA right-sizing, ACM namespace optimization, and AI/ML model serving (vLLM/GPU).

All dashboards are provisioned automatically via the Grafana Operator using ConfigMaps in [../generated/](../generated/). Run `make` in [../](../) to regenerate ConfigMaps after editing JSON files here.

---

## Dashboards

| # | Dashboard | UID | Refresh | Time Range | Key Metrics |
|---|-----------|-----|---------|------------|-------------|
| 1 | [Admin: API & Network Analysis](#1-admin-api--network-analysis) | `net-status-adv` | 5s | 1h | HTTP status codes, latency, network I/O |
| 2 | [Admin: Cluster Health](#2-admin-cluster-health) | `d192c7df-...` | 10s | 6h | Nodes, GPU (DCGM), pods, OOMKill, CrashLoop |
| 3 | [Admin: OCP Cluster Overview](#3-admin-ocp-cluster-overview) | `d74d470f-...` | 10s | 6h | Capacity vs usage, HAProxy, disk pressure |
| 4 | [Admin: VPA Optimization & Health](#4-admin-vpa-optimization--health) | `vpa-comprehensive` | — | 6h | VPA recommendations vs actual provisioning |
| 5 | [ACM: Right-Sizing Namespace](#5-acm-right-sizing-namespace) | `bnqQIPySE` | — | 7d | ACM right-sizing CPU/memory per namespace |
| 6 | [RHOAI: GPU Utilization & Consumption](#6-rhoai-gpu-utilization--consumption) | `87d09980-...` | 10s | 6h | DCGM GPU util, VRAM, temp, power |
| 7 | [RHOAI: Inference Endpoint Monitoring](#7-rhoai-inference-endpoint-monitoring) | `ron9fzt` | 10s | 6h | HAProxy success rate, 4xx/5xx, vLLM outcomes |
| 8 | [RHOAI: vLLM & GPU Master Dashboard](#8-rhoai-vllm--gpu-master-dashboard) | `60699702-...` | 10s | 6h | RPS, P95 latency, KV cache, GPU util |
| 9 | [RHOAI: vLLM Performance Monitor](#9-rhoai-vllm-performance-monitor) | `perf-triple-ns-1` | 10s | 1h | Ingress vs app traffic, TTFT, TPOT, pod resources |
| 10 | [vLLM: Advanced Performance Dashboard](#10-vllm-advanced-performance-dashboard) | `vllm-advanced-performance` | 5s | 15m | Latency P50/P95/P99, KV cache hit rate, queue depth |

---

## Prerequisites by Dashboard

| Requirement | Dashboards |
|---|---|
| `kube-state-metrics` | 1, 2, 3, 4 |
| `node-exporter` | 2, 3 |
| OpenShift HAProxy metrics (`haproxy_*`) | 3, 7, 9 |
| NVIDIA GPU Operator / DCGM Exporter | 2, 3, 6, 8, 9 |
| VPA deployed + kube-state-metrics CRD support | 4 |
| Red Hat ACM with right-sizing enabled | 5 |
| vLLM runtime exposing Prometheus metrics | 7, 8, 9, 10 |

---

## Datasource

All dashboards use a `DS_PROMETHEUS` template variable (type: datasource) so the datasource UID resolves dynamically — required for the Grafana Operator where UIDs are assigned at deploy time.

**Exception:** The ACM Right-Sizing dashboard uses a variable named `datasource` (legacy). If you import it manually it will prompt for the datasource; it works correctly but the variable name differs from the other dashboards.

---

## 1. Admin: API & Network Analysis

High-level view of HTTP API health, status code distribution, and cluster network traffic. Useful for quickly spotting ingress degradation or network saturation.

### Panels

#### HTTP Status Codes
| Panel | Query | Description |
|---|---|---|
| Requests per Second | `sum by (code) (rate(http_requests_total[1m]))` | Request rate grouped by HTTP status code |
| 5xx Errors (1h) | `sum(increase(http_requests_total{code=~"5.."}[1h]))` | Server error count over last hour |
| Success Rate % | `sum(rate(http_requests_total{code!~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100` | Non-5xx percentage. Green >99%, Orange <99%, Red <95% |
| Total 4xx Errors (1h) | `sum(increase(http_requests_total{code=~"4.."}[1h]))` | Client error count over last hour |

#### Latency & Performance
| Panel | Query | Description |
|---|---|---|
| Global Latency (P99 & P95) | `histogram_quantile(0.99/0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))` | Response time at P99 and P95 |
| Top 5 Busiest Pods | `topk(5, sum by (pod) (rate(http_requests_total[5m])))` | Highest-traffic pods; useful for detecting load imbalance |

#### Network Traffic
| Panel | Query | Description |
|---|---|---|
| Network Bandwidth (In vs Out) | `container_network_receive/transmit_bytes_total` | Bytes/sec for vLLM/LLM namespaces |
| Network Health (Dropped Packets) | `container_network_receive/transmit_packets_dropped_total` | Non-zero values indicate CNI issues |

**Prerequisites:** Prometheus datasource, application `http_requests_total` metrics, cAdvisor/kubelet

**Tags:** `network`, `http`, `status-codes`, `detailed`

---

## 2. Admin: Cluster Health

"Single Pane of Glass" for overall cluster health — infrastructure (nodes, GPU, network) through to workload stability (pods, OOMKills, CrashLoops). Includes per-node breakdown and NVIDIA GPU health via DCGM.

**Variables:** `DS_PROMETHEUS`, `namespace`

### Panels

#### Cluster Health Overview
| Panel | Query | Description |
|---|---|---|
| Cluster Version | `max by (version) (cluster_version{type="current"})` | Current OCP version |
| Ready / Unready Nodes | `kube_node_status_condition{condition="Ready"}` | Node availability at a glance |
| Firing Alerts | `sum(ALERTS{alertstate="firing", severity=~"warning\|critical"})` | Active warning/critical alerts |
| CPU Utilization % | `100 * (1 - sum(rate(node_cpu_seconds_total{mode="idle"}[5m])) / sum(rate(node_cpu_seconds_total[5m])))` | Cluster-wide CPU usage |
| Memory Utilization % | `100 * (1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))` | Cluster-wide memory usage |

#### Node-Level Breakdown
Per-node CPU and memory utilization time-series for hot-node identification.

#### GPU Monitoring (DCGM)
| Panel | Query | Description |
|---|---|---|
| Avg GPU Utilization % | `avg(DCGM_FI_DEV_GPU_UTIL)` | Cluster-wide GPU compute usage |
| Avg GPU VRAM % | `100 * avg(DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE))` | VRAM saturation |
| GPU Temperature | `avg(DCGM_FI_DEV_GPU_TEMP)` | Thermal health (throttle risk >85°C) |
| Total Power Draw | `sum(DCGM_FI_DEV_POWER_USAGE)` | Aggregate GPU power (Watts) |

#### Workload & Events
OOMKill timeline, CrashLoopBackOff tracker, pod status breakdown, top restart table.

**Prerequisites:** kube-state-metrics, node-exporter, NVIDIA GPU Operator / DCGM Exporter

**Tags:** `kubernetes`, `openshift`, `gpu`, `nvidia`, `cluster`

---

## 3. Admin: OCP Cluster Overview

Infrastructure-first view bridging physical node health with workload stability. Includes HAProxy ingress traffic (OpenShift Router), GPU inventory, and disk pressure monitoring.

**Variables:** `DS_PROMETHEUS`, `namespace`

### Panels

#### Cluster Health & Node Status
Ready/Unready nodes, CrashLoop count, OOMKill timeline, running vs failed pods.

#### Resource Budget (Capacity vs Allocated vs Usage)
| Panel | Description |
|---|---|
| CPU Overview | Allocatable cores vs requested by pods; shows free headroom |
| Memory Overview | Total RAM vs pod memory requests |
| GPU Overview | Physical GPU count vs GPU resources claimed (`nvidia.com/gpu`) |

#### Workload & Traffic
| Panel | Query | Description |
|---|---|---|
| ReplicaSet Health | `kube_replicaset_spec_replicas` vs `kube_replicaset_status_replicas` | Gap = scheduling failure |
| Ingress Traffic by Status Code | `haproxy_backend_http_responses_total` | HTTP response codes via OpenShift HAProxy |

#### Storage & Node Pressure
DiskPressure node count, root filesystem usage % per node.

**Prerequisites:** kube-state-metrics, node-exporter, OpenShift HAProxy metrics

**Tags:** `kubernetes`, `ocp`, `infrastructure`

---

## 4. Admin: VPA Optimization & Health

Tracks VPA adoption, recommendation trends, and compares VPA targets against actual pod limits/requests for data-driven right-sizing.

**Variables:** `DS_PROMETHEUS`, `namespace`, `vpa`

### Panels

| Panel | Query | Description |
|---|---|---|
| Total VPAs Monitored | `count(max by (verticalpodautoscaler, namespace) (...))` | Active VPA objects in selected namespace |
| VPA Update Mode Distribution | `kube_customresource_verticalpodautoscaler_spec_updatepolicy_updatemode` | Pie chart: Auto / Off / Initial / Recreate |
| CPU Recommendations Over Time | `kube_customresource_verticalpodautoscaler_status_recommendation_containerrecommendations_target_cpu` | Per-container VPA CPU target trend |
| Memory Recommendations Over Time | `...target_memory` | Per-container VPA memory target trend |
| VPA Recommendations vs Actual | Multi-query: LowerBound, Target, UpperBound vs Requests and Limits | Master right-sizing table for identifying waste or risk |

**Prerequisites:** kube-state-metrics with VPA CRD support, VPA deployed

**Tags:** `vpa`, `autoscaling`, `kubernetes`

---

## 5. ACM: Right-Sizing Namespace

Uses ACM right-sizing recording rules (`acm_rs:*`) to identify over-provisioned namespaces across the fleet. Compares CPU and memory usage against requests and ACM recommendations.

**Variables:** `datasource`, `cluster`, `profile`, `days`

> **Note:** This dashboard requires Red Hat ACM with the right-sizing feature and ACM Observability (Thanos) configured to collect `acm_rs:*` recording rules from managed clusters. It will not work without ACM.

### Panels

#### CPU Right-Sizing
ACM CPU recommendation, actual usage, current requests, utilization ratio, top 20 namespaces by CPU efficiency.

#### Memory Right-Sizing
ACM memory recommendation, actual usage, current requests, utilization ratio, top 20 namespaces by memory efficiency.

**Prerequisites:** Red Hat ACM with right-sizing + ACM Observability

**Tags:** `ACM`, `Right-Sizing`

---

## 6. RHOAI: GPU Utilization & Consumption

Deep dive into NVIDIA GPU performance and health within RHOAI, scoped to specific pods and namespaces. Powered by DCGM Exporter.

**Variables:** `DS_PROMETHEUS`, `namespace`, `pod`

### Panels

| Panel | Query | Description |
|---|---|---|
| GPU Duty Cycle (%) | `avg by (pod, device) (DCGM_FI_DEV_GPU_UTIL{namespace="$namespace", pod=~"$pod"})` | Active compute time per pod/device |
| VRAM Used (Absolute) | `max by (pod, device) (DCGM_FI_DEV_FB_USED{...}) * 1024 * 1024` | VRAM in bytes per device |
| VRAM Saturation (%) | `DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) * 100` | >100% = OOM risk |
| Power Usage (W) | `DCGM_FI_DEV_POWER_USAGE{namespace="$namespace", pod=~"$pod"}` | Per-GPU instantaneous power |
| GPU Temperature | `DCGM_FI_DEV_GPU_TEMP{namespace="$namespace", pod=~"$pod"}` | Core temp; >85°C risks throttling |

**Prerequisites:** NVIDIA GPU Operator / DCGM Exporter

**Tags:** `rhoai`, `gpu`, `nvidia`, `ai`, `ml`, `monitoring`

---

## 7. RHOAI: Inference Endpoint Monitoring

Monitors AI inference endpoint health by correlating OpenShift HAProxy ingress metrics with internal vLLM engine metrics. Covers success rates, error breakdown, and request outcomes.

**Variables:** `DS_PROMETHEUS`, `namespace`, `route`, `interval`

### Panels

| Panel | Query | Description |
|---|---|---|
| Global Success Rate (%) | `sum(rate(haproxy_backend_http_responses_total{code=~"2.."}[$interval])) / sum(rate(...)) * 100` | Green >95%, Orange >80%, Red <80% |
| Total 4xx Errors | `sum by (code) (increase(haproxy_backend_http_responses_total{code=~"4.."}[$interval]))` | Client errors (bad request, auth failure) |
| Total 5xx Errors | `sum by (code) (increase(haproxy_backend_http_responses_total{code=~"5.."}[$interval]))` | Server errors (crash, timeout) |
| vLLM Request Outcomes | `sum by (finished_reason) (rate(vllm:request_success_total{namespace="$namespace"}[$interval]))` | stop / length / abort breakdown |
| vLLM Aborts | `sum(rate(vllm:request_success_total{finished_reason="abort"}[$interval]))` | Client disconnects / upstream timeouts |

**Prerequisites:** OpenShift Router (HAProxy) metrics, vLLM Prometheus metrics

**Tags:** `rhoai`, `vllm`, `inference`, `nvidia`, `redhat`

---

## 8. RHOAI: vLLM & GPU Master Dashboard

"Single Pane of Glass" for LLMs on RHOAI. Correlates vLLM application metrics (latency, queue, cache) with NVIDIA GPU hardware metrics in one view.

**Variables:** `DS_PROMETHEUS`, `namespace`, `pod` (multi-select), `interval`

### Panels

#### Executive KPIs
| Panel | Query | Description |
|---|---|---|
| Current RPS | `sum(rate(vllm:request_success_total{...}[$interval]))` | Successful requests per second |
| Avg Latency (P95) | `histogram_quantile(0.95, sum(rate(vllm:e2e_request_latency_seconds_bucket{...}[$interval])) by (le))` | End-to-end P95 latency |
| Concurrency | `sum(vllm:num_requests_running{...})` | Active parallel requests |
| GPU Utilization | `avg(DCGM_FI_DEV_GPU_UTIL{...})` | Average compute utilization |

#### Model Performance
TTFT P95, TPOT P95, latency breakdown by queue / prefill / decode phase.

#### Throughput & Queue
Token throughput (prompt vs generation), running vs waiting request counts (saturation signal).

#### KV Cache
GPU and CPU cache usage %, prefix cache hit rate.

**Prerequisites:** vLLM metrics, NVIDIA GPU Operator

**Tags:** `vllm`, `rhoai`, `gpu`

---

## 9. RHOAI: vLLM Performance Monitor

Full-stack performance trace: Ingress → Model → GPU. Uses a triple-namespace selector (`vllm_ns`, `gpu_ns`, `ingress_ns`) so metrics can be correlated even when components are in different namespaces. Also exposes pod-level CPU/memory for the vLLM containers.

**Variables:** `DS_PROMETHEUS`, `vllm_ns`, `vllm_pod`, `gpu_ns`, `gpu_pod`, `interval`

### Panels

| Section | Key Panels |
|---|---|
| Traffic Flow | Ingress sessions vs app successes (gap = dropped requests), HAProxy error rates |
| Latency | HAProxy avg response time vs vLLM TTFT/TPOT P95 (isolates network vs model lag) |
| Application Network | Pod-level bandwidth and packet drops (`container_network_*`) |
| GPU Resources | Per-pod GPU utilization and VRAM usage |
| System Resources | vLLM pod CPU and memory working set |

**Prerequisites:** OpenShift Router metrics, vLLM metrics, DCGM Exporter, cAdvisor/kubelet

**Tags:** `performance`, `triple-split-ns`, `traffic-analysis`

---

## 10. vLLM: Advanced Performance Dashboard

Deepest vLLM observability — latency distributions (P50/P95/P99), KV cache internals, and throughput analysis at the per-pod level. Does not require GPU Operator metrics.

**Variables:** `DS_PROMETHEUS`, `model`

### Panels

#### Latency Analysis
| Panel | Queries | Description |
|---|---|---|
| Time to First Token (TTFT) | `histogram_quantile(0.50/0.95, rate(vllm:time_to_first_token_seconds_bucket[5m]))` | P50/P95; high TTFT = prefill bottleneck |
| Inter-Token Latency (TPOT) | `histogram_quantile(0.50/0.95, rate(vllm:time_per_output_token_seconds_bucket[5m]))` | P50/P95; high TPOT = GPU saturated |
| End-to-End Latency | `histogram_quantile(0.50/0.95, rate(vllm:e2e_request_latency_seconds_bucket[5m]))` | Full request lifecycle; use for SLA monitoring |

#### KV Cache Efficiency
| Panel | Description |
|---|---|
| GPU Memory Blocks | KV cache blocks allocated; thresholds: Green <40K, Yellow <60K, Red >60K |
| KV Cache Hit Rate | `vllm:gpu_prefix_cache_hits_total / vllm:gpu_prefix_cache_queries_total`; Green >60% |
| Per-Pod Cache Hit Rates | Bar chart of cache efficiency per pod; identifies uneven routing |

#### Throughput & Queue
Running vs waiting requests (saturation signal), request throughput vs success rate, token processing rates.

**Prerequisites:** vLLM Prometheus metrics (no GPU Operator required)

**Tags:** `llm`, `vllm`, `performance`, `inference`
