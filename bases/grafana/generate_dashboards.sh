#!/bin/bash

# Configuration matching your screenshot structure
SOURCE_DIR="./dashboard"
OUTPUT_DIR="./generated"
NAMESPACE="openshift-operators"  # Change if needed

# Clean and recreate output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "🚀 Generating GrafanaDashboard Custom Resources..."

# --- [PART 1] Loop through JSONs and convert to YAML ---
for json_file in "$SOURCE_DIR"/*.json; do
    # Skip if no JSON files found
    [ -e "$json_file" ] || continue

    # Clean filename for K8s resource name (lowercase, no spaces)
    filename=$(basename "$json_file" .json)
    # Replaces spaces/underscores with dashes, removes weird chars, ensures lowercase
    k8s_name=$(echo "$filename" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed 's/[^a-z0-9-]//g')

    output_file="$OUTPUT_DIR/$k8s_name.yaml"

    echo "   📄 Converting: $filename -> $output_file"

    # Write YAML Header
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

    # Indent the JSON content by 4 spaces and append it
    sed 's/^/    /' "$json_file" >> "$output_file"
done

# --- [PART 2] Generate the kustomization.yaml (ADD THIS HERE) ---
echo "📦 Generating kustomization.yaml for the output folder..."

echo "resources:" > "$OUTPUT_DIR/kustomization.yaml"

# Loop through the new YAML files we just created
for yaml_file in "$OUTPUT_DIR"/*.yaml; do
    # Don't add kustomization.yaml to itself!
    filename=$(basename "$yaml_file")
    if [ "$filename" != "kustomization.yaml" ]; then
        echo "  - $filename" >> "$OUTPUT_DIR/kustomization.yaml"
    fi
done

echo "✅ Done! YAMLs and Kustomization are in $OUTPUT_DIR"