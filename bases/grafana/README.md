# 🛠️ Grafana Dashboard Automation

This project includes an automation workflow to convert standard **Grafana JSON** dashboard files into Kubernetes-native **`GrafanaDashboard` Custom Resources (CRs)**. This facilitates a GitOps approach, allowing you to manage dashboards as code and deploy them via ArgoCD, Flux, or direct `oc apply`.

## 🚀 How It Works

The workflow consists of two main components:
1.  **`generate_dashboards.sh`**: A shell script that performs the conversion logic, sanitizing names and wrapping JSON in YAML.
2.  **`Makefile`**: A task runner that simplifies execution and ensures permissions are correct.

**Workflow:**
`Raw JSON` (`./dashboard/*.json`) ➔ **`make dashboards`** ➔ `Kubernetes YAML` (`./generated/*.yaml`) + `kustomization.yaml`

---

## 📋 Prerequisites

To use this automation, ensure your environment meets the following requirements:

* **Bash Shell:** The script relies on standard bash utilities (`cat`, `sed`, `tr`, `basename`).
* **Make:** Required to run the `make dashboards` command.
* **Kustomize:** (Optional but recommended) Useful for validating and consolidating the output.
* **Grafana Operator:** The generated YAMLs use the `grafana.integreatly.org/v1beta1` API and assume a Grafana instance is listening for the label `dashboards: grafana-a`.

---

## 📂 Directory Structure

Your repository should be structured as follows:

```text
.
├── Makefile                   # The task runner
├── generate_dashboards.sh     # The conversion script
├── dashboard/                 # 📂 INPUT: Place raw Grafana JSON files here
│   ├── my-dashboard.json
│   └── vllm-metrics.json
└── generated/                 # 📂 OUTPUT: Generated YAMLs appear here (Git ignored usually)
    ├── my-dashboard.yaml
    ├── vllm-metrics.yaml
    └── kustomization.yaml