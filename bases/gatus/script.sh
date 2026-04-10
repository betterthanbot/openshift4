#!/bin/bash

# Ensure the user is logged into OpenShift
oc whoami >/dev/null 2>&1 || { echo "Error: You must be logged in to OpenShift via 'oc login' first."; exit 1; }

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required to parse the JSON output. Please install it."
    exit 1
fi

OUTPUT_FILE="gatus-full-config.yaml"

echo "Generating Unified Gatus ConfigMap..."

# 1. Write the static header of the Gatus ConfigMap
cat <<EOF > $OUTPUT_FILE
apiVersion: v1
kind: ConfigMap
metadata:
  name: gatus-config
  labels:
    app: gatus
data:
  config.yaml: |
    ui:
      title: "Platform Status Dashboard"
      header: "API, Route & Internal Probe Health"
      description: "Real-time health status of OpenShift services and internal microservices"
      logo: "https://upload.wikimedia.org/wikipedia/commons/3/3a/OpenShift-LogoType.svg"
      theme: "dark"
    
    storage:
      type: sqlite
      path: /data/gatus.db
    
    endpoints:
EOF

# 2. Fetch and append OpenShift Routes
echo " -> Scraping OpenShift Routes..."
oc get route --all-namespaces -o json | jq -r '
  .items[] |
  "      - name: \"\(.metadata.name) (Route)\"\n" +
  "        group: \"\(.metadata.namespace)\"\n" +
  "        url: \"\(if .spec.tls != null then "https" else "http" end)://\(.spec.host)\(if .spec.path != null then .spec.path else "" end)\"\n" +
  "        interval: 1m\n" +
  "        conditions:\n" +
  "          - \"[STATUS] >= 200\"\n" +
  "          - \"[STATUS] <= 499\"\n"
' >> $OUTPUT_FILE

# 3. Fetch and append Internal Readiness Probes
echo " -> Scraping Internal Deployment Probes..."
oc get deployment,dc -A -o json | jq -r '
  .items[] | 
  .metadata.namespace as $ns |
  .metadata.name as $app |
  .spec.template.spec.containers[]? |
  select(.readinessProbe.httpGet != null) |
  .readinessProbe.httpGet as $probe |
  (if $probe.scheme then ($probe.scheme | ascii_downcase) else "http" end) as $scheme |
  "      - name: \"\($app) (\(.name) Probe)\"\n" +
  "        group: \"\($ns)\"\n" +
  "        url: \"\($scheme)://\($app).\($ns).svc.cluster.local:\($probe.port)\($probe.path // "/")\"\n" +
  "        interval: 1m\n" +
  "        conditions:\n" +
  "          - \"[STATUS] >= 200\"\n" +
  "          - \"[STATUS] <= 499\"\n"
' >> $OUTPUT_FILE

echo "Success! Your unified configuration has been generated and saved to: $OUTPUT_FILE"