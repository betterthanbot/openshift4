#!/bin/bash

SOURCE_DIR="./dashboard"
OUTPUT_DIR="./generated"
NAMESPACE="openshift-operators" 

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "🚀 Generating GrafanaDashboard Custom Resources..."

for json_file in "$SOURCE_DIR"/*.json; do
    [ -e "$json_file" ] || continue

    filename=$(basename "$json_file" .json)
    k8s_name=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed 's/[^a-z0-9-]//g')
    output_file="$OUTPUT_DIR/$k8s_name.yaml"
    echo "   📄 Converting: $filename -> $output_file"

    cat <<EOF > "$output_file"
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: $k8s_name
  namespace: $NAMESPACE
spec:
  instanceSelector:
    matchLabels:
      dashboards: grafana-a
  json: |
EOF

    sed 's/^/    /' "$json_file" >> "$output_file"
done

echo "📦 Generating kustomization.yaml for the output folder..."

echo "resources:" > "$OUTPUT_DIR/kustomization.yaml"

for yaml_file in "$OUTPUT_DIR"/*.yaml; do
    filename=$(basename "$yaml_file")
    if [ "$filename" != "kustomization.yaml" ]; then
        echo "  - $filename" >> "$OUTPUT_DIR/kustomization.yaml"
    fi
done

echo "✅ Done! YAMLs and Kustomization are in $OUTPUT_DIR"