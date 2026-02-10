# 📊 RHOAI & Cluster Monitoring Dashboards

This repository contains a suite of 7 production-ready Grafana dashboards designed for Red Hat OpenShift AI (RHOAI) and Kubernetes environments. These dashboards provide end-to-end visibility, ranging from physical cluster infrastructure to high-level API traffic and specific AI model performance (vLLM/GPU).

## 📑 Table of Contents

1.  [Admin: API & Network Analysis](#1-admin-api--network-analysis-dashboard)
2.  [Admin: Cluster Health](#2-admin-cluster-health-dashboard)
3.  [Admin: OCP Cluster Overview](#3-admin-ocp-cluster-overview-dashboard)
4.  [RHOAI: GPU Utilization & Consumption](#4-rhoai-gpu-utilization--consumption)
5.  [RHOAI: Inference Endpoint Monitoring](#5-rhoai-inference-endpoint-monitoring)
6.  [RHOAI: vLLM & GPU Master Dashboard](#6-rhoai-vllm--gpu-master-dashboard)
7.  [RHOAI: vLLM Performance Monitor](#7-rhoai-vllm-performance-monitor)

---

## 1. 🚦 Admin: API & Network Analysis Dashboard

This Grafana dashboard provides a high-level overview of API health, HTTP status codes, and cluster network traffic. It is designed to help SREs and Administrators quickly identify API degradation, high error rates, or network saturation issues within the cluster.

### 📸 Screenshots

![Dashboard Preview](images/admin_api_network_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### 🚦 HTTP Status Codes (API Health)
This section focuses on the reliability of your HTTP services (Ingress/API).

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Requests per Second** | `http_requests_total` OR `nginx_ingress_controller_requests` | Displays the real-time traffic rate (RPS), broken down by HTTP Status Code (200s, 400s, 500s). Green lines indicate success, while red/orange indicate errors. |
| **5xx Errors (1h)** | `increase(http_requests_total{code=~"5.."}[1h])` | The total count of server-side errors (Internal Server Errors) over the last hour. If this number is rising, the application is crashing or failing. |
| **Success Rate %** | Derived from `http_requests_total` | A gauge showing the percentage of non-5xx requests. <br>• **Green:** > 99% <br>• **Orange:** < 99% <br>• **Red:** < 95% |
| **Total 4xx Errors (1h)** | `increase(http_requests_total{code=~"4.."}[1h])` | The total count of client-side errors (Bad Request, Unauthorized) over the last hour. High numbers here usually indicate bad client configurations or aggressive scanning. |

#### ⏱️ Latency & Performance
This section tracks how fast the application is responding to users.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Global Latency (P99 & P95)** | `http_request_duration_seconds_bucket` | Calculates the histogram quantiles for response time.<br>• **P99:** The slowest 1% of requests (worst-case scenario).<br>• **P95:** The standard for "slow" requests. |
| **Top 5 Busiest Pods** | `topk(5, rate(http_requests_total))` | Identifies the top 5 pods handling the most traffic. Useful for identifying "hotspots" or load-balancing issues. |

#### 🌐 Network Traffic (Cluster I/O)
This section monitors the raw networking throughput and health of the underlying containers (specifically targeting `vllm` or `llm` namespaces).

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Network Bandwidth (In vs Out)** | `container_network_receive_bytes_total`<br>`container_network_transmit_bytes_total` | Measures the data throughput in Bytes/sec. Essential for detecting network saturation or large file transfers. |
| **Network Health (Dropped Packets)** | `container_network_receive_packets_dropped_total`<br>`container_network_transmit_packets_dropped_total` | Counts the rate of dropped packets. Any value above 0 indicates network congestion, CNI issues, or hardware limits being reached. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or the default datasource).
2.  **Metrics Exporters:**
    * **Application Metrics:** Your apps must export standard Prometheus HTTP metrics (`http_requests_total`, `http_request_duration_seconds_bucket`).
    * **cAdvisor / Kubelet:** Required for `container_network_*` metrics.
    * **Ingress Controller:** (Optional) If using NGINX Ingress, it will pick up `nginx_ingress_controller_requests`.

### 🏷️ Tags
`network`, `http`, `status-codes`, `detailed`, `sre`

---

## 2. 🏥 Admin: Cluster Health Dashboard

This Grafana dashboard serves as a comprehensive "Single Pane of Glass" for monitoring the overall health, capacity, and stability of your Kubernetes/OpenShift cluster. It aggregates infrastructure-level metrics (Nodes) with workload-level status (Pods, Deployments), focusing on stability indicators like OOMKills and CrashLoops.

### 📸 Screenshots

![Cluster Health Preview](images/admin_cluster_health_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### 🏗️ Cluster Infrastructure (Nodes)
This section provides a high-level view of the physical/virtual infrastructure health.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Cluster Versions** | `cluster_version` | Displays the current OpenShift/Kubernetes version. Essential for tracking upgrades and compliance. |
| **Cluster Capacity vs Commit (CPU)** | `kube_node_status_allocatable`<br>`kube_pod_container_resource_requests` | Compares the total CPU capacity of the cluster against the total CPU requested by pods. Helps identify over-provisioning or capacity bottlenecks. |
| **Cluster Capacity vs Commit (Memory)** | `kube_node_status_allocatable`<br>`kube_pod_container_resource_requests` | Similar to CPU, but for RAM. Critical for preventing node-level OOMs. |
| **✅ Ready Nodes** | `kube_node_status_condition{condition="Ready", status="true"}` | Count of healthy nodes available to schedule workloads. |
| **❌ Unready Nodes** | `kube_node_status_condition{condition="Ready", status!="true"}` | Count of broken or disconnected nodes. Any value > 0 requires immediate attention. |

#### 📦 Workload Summary
This section summarizes the state of applications running on the cluster.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Total Deployments** | `kube_deployment_status_replicas` | The total number of deployment replicas currently desired/running. |
| **Total ReplicaSets** | `kube_replicaset_status_ready_replicas` | The number of ReplicaSets that have ready replicas. |
| **Total Pod Count** | `kube_pod_info` | The absolute count of pods in the selected namespace(s). |
| **Pod Status Breakdown** | `kube_pod_status_phase` | A pie chart visualization of pods by phase (Running, Pending, Failed, Succeeded). |

#### ⚠️ Critical Events & Errors
This is the "Stability" section, designed to catch application crashes and resource starvation.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **OOMKilled Timeline** | `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` | Tracks pods that were killed by the kernel due to running out of memory limits. Spikes here indicate undersized memory requests. |
| **CrashLoopBackOff** | `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}` | Tracks pods that are failing to start repeatedly (e.g., config errors, missing dependencies). |

#### 📋 Pod Details Table
A detailed list for drilling down into specific problem pods.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Pod Stability List** | `kube_pod_container_status_restarts_total` | Lists pods sorted by their restart count. High restart counts usually indicate unstable applications or liveness probe failures. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or selects one via the `$DS_PROMETHEUS` variable).
2.  **kube-state-metrics:** This is the core requirement. All metrics starting with `kube_` (e.g., `kube_pod_info`, `kube_node_status_condition`) come from this standard exporter. Most OpenShift and K8s distributions have this installed by default.

### 🏷️ Tags
`kubernetes`, `cluster`, `admin`, `health`, `capacity`

---

## 3. 🏥 Admin: OCP Cluster Overview Dashboard

This Grafana dashboard provides a comprehensive "Infrastructure-First" view of your OpenShift Container Platform (OCP) cluster. It is designed to bridge the gap between physical node health (CPU/Memory/Disk) and application workload stability (ReplicaSets, CrashLoops, Ingress). It is ideal for Cluster Admins and SREs who need to answer "Is the cluster healthy?" at a glance.

### 📸 Screenshots

![OCP Cluster Overview Preview](images/admin_cluster_overview_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### 🏗️ Cluster Health & Node Status
This section provides immediate "Red/Green" status indicators for the cluster's physical infrastructure and critical pod states.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Ready Nodes** | `kube_node_status_condition{condition="Ready", status="true"}` | Count of healthy nodes currently online and accepting workloads. |
| **Unready Nodes** | `kube_node_status_condition{condition="Ready", status!="true"}` | Count of offline or partitioned nodes. A non-zero value here is a critical alert. |
| **Pods in CrashLoop** | `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}` | The number of pods currently stuck in a restart loop. Useful for spotting broken deployments immediately. |
| **⚠️ OOMKilled Pods (Timeline)** | `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` | A time-series graph showing when pods were killed due to Out-Of-Memory errors. Peaks indicate memory sizing issues. |
| **Total Deployments** | `kube_deployment_status_observed_generation` | Total number of Deployment objects in the selected namespace(s). |
| **Total Running Pods** | `kube_pod_status_phase{phase="Running"}` | Count of pods in the "Running" phase. |
| **Failed Pods** | `kube_pod_status_phase{phase=~"Failed|Unknown"}` | Count of pods that have terminated with an error or are in an unknown state. |

#### 🔋 Resources: Capacity vs Allocated vs Usage
This section visualizes the cluster's "Resource Budget." It helps you understand if you are running out of physical capacity or if you have simply reserved too much (over-provisioning).

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **CPU Overview (Cores)** | `kube_node_status_allocatable`<br>`kube_pod_container_resource_requests` | Compares Total Cluster CPU cores vs. CPU Cores requested by workloads. Shows "Free to Allocate" capacity. |
| **Memory Overview (RAM)** | `kube_node_status_allocatable`<br>`kube_pod_container_resource_requests` | Compares Total Cluster RAM vs. RAM requested by workloads. |
| **GPU Overview (Count)** | `kube_node_status_allocatable{resource="nvidia.com/gpu"}` | Tracks NVIDIA GPU inventory. Shows how many GPUs are physically available vs. how many are claimed by pods. |

#### 🚦 Workload & Traffic
This section monitors the scalability and external traffic flow of your applications.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **ReplicaSet Health** | `kube_replicaset_spec_replicas`<br>`kube_replicaset_status_replicas` | Compares "Desired" vs "Current" replicas. A gap between these lines indicates the cluster cannot schedule new pods (likely due to resource exhaustion). |
| **Ingress Traffic by Status Code** | `haproxy_backend_http_responses_total` | Tracks HTTP response codes (2xx, 4xx, 5xx) flowing through the OpenShift HAProxy Ingress. Useful for spotting application-level errors. |

#### 💾 Storage & Node Pressure
This section focuses on disk health, ensuring nodes don't fail due to full filesystems.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Disk Pressure Alert** | `kube_node_status_condition{condition="DiskPressure", status="true"}` | Counts nodes reporting "DiskPressure." If > 0, pods will be evicted to free up space. |
| **Disk Usage % (Root Filesystem)** | `node_filesystem_size_bytes`<br>`node_filesystem_free_bytes` | Shows the percentage of disk space used on the root (`/`) filesystem for each node. High usage (>85%) typically warrants cleanup. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or selects one via the `$DS_PROMETHEUS` variable).
2.  **kube-state-metrics:** Required for all `kube_*` metrics (Node status, Pod phases, Resource requests).
3.  **node-exporter:** Required for disk usage metrics (`node_filesystem_*`).
4.  **HAProxy / Ingress Controller:** Required for `haproxy_*` metrics (OpenShift default router exports these).

### 🏷️ Tags
`kubernetes`, `ocp`, `infrastructure`, `admin`, `capacity`, `gpu`

---

## 4. 🧠 RHOAI: GPU Utilization & Consumption

This dashboard provides a deep dive into the performance and health of NVIDIA GPUs within a Red Hat OpenShift AI (RHOAI) environment. It uses metrics from the **NVIDIA DCGM Exporter** to visualize how effectively your AI/ML models are utilizing the underlying hardware, tracking compute load, VRAM consumption, and physical health stats like power and temperature.

### 📸 Screenshots

![RHOAI GPU Preview](images/admin_gpu_util_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### ⚡ Compute Utilization (How busy is the chip?)
This section helps you determine if your models are actually using the GPU compute cycles or if they are sitting idle.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **GPU Duty Cycle (Utilization %)** | `DCGM_FI_DEV_GPU_UTIL` | A time-series graph showing the percentage of time the GPU kernels were active. High usage (80-90%) indicates an efficient workload; low usage implies bottlenecks elsewhere (e.g., data loading). |
| **Current Utilization** | `avg(DCGM_FI_DEV_GPU_UTIL)` | A gauge showing the real-time average utilization across selected pods. |

#### 💾 Memory Consumption (VRAM)
Monitoring VRAM is critical for AI workloads. "OOM" (Out of Memory) errors here cause immediate training/inference crashes.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **VRAM Used (Absolute)** | `DCGM_FI_DEV_FB_USED` | The actual amount of Frame Buffer (VRAM) memory currently allocated by the model, displayed in Gigabytes (GB). |
| **VRAM Saturation (%)** | `(Used / (Used + Free)) * 100` | Displays memory usage as a percentage of the total card capacity. If this consistently hits 100%, you need a larger GPU or a smaller batch size. |

#### 🌡️ Hardware Health
This section monitors the physical state of the cards to detect throttling or hardware failure.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Power Usage (Watts)** | `DCGM_FI_DEV_POWER_USAGE` | The instantaneous power draw of the GPU. Useful for capacity planning and identifying "power virus" workloads. |
| **GPU Temperature** | `DCGM_FI_DEV_GPU_TEMP` | The core temperature of the GPU in Celsius. Sustained high temps (>85°C) may lead to thermal throttling, slowing down your AI models. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or selects one via the `$DS_PROMETHEUS` variable).
2.  **NVIDIA GPU Operator:** This dashboard relies on the `nvidia-dcgm-exporter`, which is automatically deployed by the NVIDIA GPU Operator in OpenShift/RHOAI.
3.  **Metrics:** Specifically, the `DCGM_FI_DEV_*` metrics must be enabled in your DCGM exporter config (this is usually the default).

### 🏷️ Tags
`rhoai`, `gpu`, `nvidia`, `ai`, `ml`, `monitoring`

---

## 5. 🧠 RHOAI: Inference Endpoint Monitoring

This dashboard provides a dedicated view for monitoring the health and traffic patterns of your AI Inference Endpoints (vLLM, TGIS, Caikit) deployed on Red Hat OpenShift AI. It correlates external traffic (via HAProxy Ingress) with internal engine metrics (vLLM request outcomes) to pinpoint whether errors are network-related or model-related.

### 📸 Screenshots

![RHOAI Inference Preview](images/rhoai_inference_endpoint_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### 🏥 Health Overview (Success Rate & Stats)
This section gives you an immediate "Green/Red" signal on the availability of your model serving endpoints.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Global Success Rate (%)** | `haproxy_backend_http_responses_total` | A gauge showing the percentage of requests returning `2xx` (Success) vs total requests. <br>• **Green:** > 95% <br>• **Orange:** > 80% <br>• **Red:** < 80% |
| **Total Traffic Volume (Counts)** | `increase(haproxy_backend_http_responses_total)` | A count of total requests over the selected interval, broken down by HTTP status code. Useful for validating load tests or traffic spikes. |

#### 🚨 Error Analysis (Total Counts)
This section isolates the bad traffic to help you debug client vs. server issues.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Total 4xx Errors (Client)** | `haproxy_backend_http_responses_total{code=~"4.."}` | Counts "Client Errors" (e.g., 400 Bad Request, 401 Unauthorized). High numbers here often mean the user is sending invalid JSON payloads or wrong authentication. |
| **Total 5xx Errors (Server)** | `haproxy_backend_http_responses_total{code=~"5.."}` | Counts "Server Errors" (e.g., 500 Internal Error, 504 Gateway Timeout). High numbers here mean the model container has crashed or timed out. |

#### ⚙️ Engine Side View (vLLM Internal Metrics)
This section looks *inside* the model server (vLLM) to see how it processed the requests.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **vLLM Request Outcomes** | `vllm:request_success_total` | Break down requests by how they finished.<br>• **stop:** Successfully generated EOS token.<br>• **length:** Hit max token limit (truncated).<br>• **abort:** Client disconnected. |
| **vLLM Aborts (Internal Timeouts)** | `vllm:request_success_total{finished_reason="abort"}` | Specific tracking for "Aborted" requests. A spike here usually means the client (or an upstream proxy) timed out and closed the connection before the model finished generating. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or selects one via the `$DS_PROMETHEUS` variable).
2.  **HAProxy / OpenShift Router:** Required for the ingress metrics (`haproxy_backend_http_responses_total`).
3.  **vLLM / RHOAI Runtime:** Your model serving runtime must be exposing standard vLLM Prometheus metrics (`vllm:request_success_total`).

### 🏷️ Tags
`rhoai`, `vllm`, `inference`, `nvidia`, `redhat`, `haproxy`

---

## 6. 🚀 RHOAI: vLLM & GPU Master Dashboard

This is the ultimate "Single Pane of Glass" for AI Engineers and SREs running Large Language Models (LLMs) on Red Hat OpenShift AI. It correlates **Application Metrics** (vLLM inference speed, queue depth, cache usage) directly with **Infrastructure Metrics** (GPU utilization, power, memory) in one unified view.

### 📸 Screenshots

![vLLM Master Preview](images/rhoai_vllm_gpu_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### 🚀 Executive Summary (KPIs)
A top-level row for quick health checks.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Current RPS** | `vllm:request_success_total` | Real-time Requests Per Second processed by the model server. |
| **Avg Latency (P95)** | `vllm:e2e_request_latency_seconds_bucket` | End-to-End latency for 95% of requests. This includes queue time + processing time. |
| **Concurrency (Active Requests)** | `vllm:num_requests_running` | The number of requests currently being processed in parallel (Batch Size). |
| **Cluster GPU Utilization** | `DCGM_FI_DEV_GPU_UTIL` | Average GPU utilization across all selected pods. |

#### ⏱️ Model Performance (Latency & Responsiveness)
Deep dive into the "User Experience" metrics.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Time to First Token (TTFT)** | `vllm:time_to_first_token_seconds_bucket` | How long a user waits before seeing the *first* word. High TTFT = Slow prefill or queueing. |
| **Time Per Output Token (TPOT)** | `vllm:time_per_output_token_seconds_bucket` | How fast the model "types" the answer. High TPOT = GPU saturation. |
| **Latency Breakdown** | `queue_time`, `prefill_time`, `decode_time` | A stacked graph showing exactly where time is spent. Is it the queue? The prompt processing? Or the generation? |

#### 🌊 Throughput & Queue Depth
Analyze the traffic volume and system saturation.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Token Throughput** | `prompt_tokens_total` vs `generation_tokens_total` | Compares "Reading Speed" (Input Tokens) vs "Writing Speed" (Output Tokens). |
| **Queue & Batching** | `num_requests_running` vs `num_requests_waiting` | Visualizes saturation. If "Waiting" > 0, the system is full and requests are queuing. |

#### 🧠 vLLM Internals (Memory & Cache)
Critical for performance tuning and preventing OOMs.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **KV Cache Usage** | `vllm:gpu_cache_usage_perc` | The percentage of GPU memory reserved for the KV Cache. If this hits 100%, vLLM will start swapping to CPU or rejecting requests. |
| **Cache Efficiency** | `request_prefix_cache_hits` | The "Hit Rate" of the prefix cache. Higher means better performance for repeated system prompts. |

#### 🔌 Infrastructure (Hardware Health)
Physical hardware stats from the NVIDIA GPU Operator.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **GPU Utilization (%)** | `DCGM_FI_DEV_GPU_UTIL` | Per-GPU core utilization. |
| **Power Usage (Watts)** | `DCGM_FI_DEV_POWER_USAGE` | Real-time power consumption per card. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or selects one via the `$DS_PROMETHEUS` variable).
2.  **vLLM Runtime:** Your model server must be vLLM, and it must be configured to export Prometheus metrics (usually on port 8000 `/metrics`).
3.  **NVIDIA GPU Operator:** Required for the hardware metrics (`DCGM_*`).

### 🏷️ Tags
`vllm`, `rhoai`, `gpu`, `nvidia`, `llm`, `genai`

---

## 7. 📈 RHOAI: vLLM Performance Monitor

This dashboard provides a detailed, full-stack performance view of your vLLM model servers running on OpenShift. It is designed to trace the request lifecycle from Ingress (Network) -> Model (Inference) -> Hardware (GPU). It features a "Triple-Namespace" selector strategy, allowing you to correlate metrics even if your Router, Application, and GPU Operator live in different namespaces.

### 📸 Screenshots

![vLLM Performance Monitor Preview](images/rhoai_vllm_performance_dashboard.png)

### 📊 Metrics & Panels Breakdown

#### 🌐 Traffic Flow (Ingress vs vLLM App)
This section compares external traffic hitting the cluster router against the requests actually processed by the application.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Inbound Traffic Comparison** | `haproxy_backend_sessions_total` vs `vllm:request_success_total` | Plots "Ingress Sessions" vs "App Successes." A gap between these two lines indicates requests are being dropped before reaching the app (e.g., firewall, router queue). |
| **Ingress Error Rates** | `haproxy_backend_response_errors_total` | Tracks 5xx errors generated by the router itself (e.g., "No backend available"). |

#### ⏱️ Latency (Network vs Model Inference)
Distinguishes between "Network Lag" and "Processing Lag."

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Network Latency** | `haproxy_backend_http_average_response_latency_milliseconds` | The time taken by the load balancer to receive a response. High latency here *with* low model latency implies network congestion. |
| **Model Inference Latency** | `vllm:time_to_first_token_seconds_bucket` | The actual time the model takes to generate the first token (TTFT). High latency here means the model is overloaded or the GPU is saturated. |

#### 📦 Application Traffic Analysis
Monitors the raw network I/O of the model pods.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **Application Bandwidth** | `container_network_receive_bytes_total` | Total data flowing in/out of the vLLM pods. Useful for sizing network policies. |
| **Packet Drops** | `container_network_receive_packets_dropped_total` | Counts dropped packets at the pod level. Any drops here indicate CNI/SDN limits are being hit. |

#### 🚀 GPU Resources
Correlates model performance with hardware usage.

| Panel Name | Metric / Query | Description |
| :--- | :--- | :--- |
| **GPU Utilization** | `DCGM_FI_DEV_GPU_UTIL` | How busy the GPU compute cores are. |
| **GPU Memory (VRAM)** | `DCGM_FI_DEV_FB_USED` | How much video memory is consumed. If this flatlines at the max, you are at risk of OOM. |

### 🛠️ Prerequisites

1.  **Prometheus Datasource:** The dashboard expects a datasource named `prometheus` (or selects one via the `$DS_PROMETHEUS` variable).
2.  **vLLM Metrics:** The application must export standard vLLM Prometheus metrics.
3.  **OpenShift Router Metrics:** Required for the `haproxy_*` queries.
4.  **DCGM Exporter:** Required for the GPU hardware stats.

### 🏷️ Tags
`performance`, `triple-split-ns`, `traffic-analysis`, `vllm`