# OpenRAG (langflow-ai/openrag) — render the upstream Helm chart into openrag.yaml.
#
#   make            # vendor the chart at OPENRAG_REF + helm template -> openrag.yaml
#   make secrets    # one-time: create the out-of-band Secrets (needs oc + a cluster login)
#
# The chart is not published to a Helm repo, so it is cloned from git (sparse, shallow)
# into vendor/ (gitignored). Commit openrag.yaml, never vendor/.

OPENRAG_REF ?= v0.8.0
OPENRAG_REPO ?= https://github.com/langflow-ai/openrag.git
NAMESPACE ?= openrag

CHART := vendor/openrag/kubernetes/helm/openrag

# The chart generates its Secrets with randAlphaNum at render time, so the output
# changes on every run and would put credentials in git. Render with fixed
# placeholders (stable checksum annotations) and drop every Secret (and the IBM-Cloud StorageClass) —
# the real ones are created out of band by `make secrets`.
PLACEHOLDERS := \
	--set-string global.opensearch.password=render-placeholder \
	--set-string langflow.auth.secretKey=render-placeholder \
	--set-string langflow.auth.superuserPassword=render-placeholder \
	--set-string backend.auth.sessionSecret=render-placeholder \
	--set-string backend.encryption.key=render-placeholder

.PHONY: all template vendor secrets clean

all: template

vendor:
	rm -rf vendor/openrag
	mkdir -p vendor
	git clone --quiet --depth 1 --branch $(OPENRAG_REF) --filter=blob:none --sparse $(OPENRAG_REPO) vendor/openrag
	git -C vendor/openrag sparse-checkout set kubernetes/helm/openrag

template: vendor
	helm template openrag $(CHART) --namespace $(NAMESPACE) -f values.yaml $(PLACEHOLDERS) \
		| python3 -I filter-render.py > openrag.yaml

# Creates the three Secrets the chart expects but we deliberately do not commit:
#   openrag-dotenv, openrag-langflow-dotenv  (the .env files the pods mount)
#   openrag-opensearch                       (admin password, also read by the OpenSearch pod)
# They are rendered by the chart itself from values.yaml so they cannot drift from it.
# SESSION_SECRET is replaced with a random value: the chart derives it deterministically
# (derivePassword from the release name), so anyone who knows the chart could compute it.
# Refuses to run twice: new passwords would no longer match the existing OpenSearch data.
secrets: vendor
	@if oc get secret openrag-dotenv -n $(NAMESPACE) >/dev/null 2>&1; then \
		echo "openrag-dotenv already exists in $(NAMESPACE); delete openrag-dotenv, openrag-langflow-dotenv and openrag-opensearch first to regenerate."; \
		exit 1; \
	fi
	@oc get namespace $(NAMESPACE) >/dev/null 2>&1 || oc create namespace $(NAMESPACE)
	@OS_PW="$$(openssl rand -hex 14)-Aa1"; LF_PW="$$(openssl rand -hex 14)"; \
	helm template openrag $(CHART) --namespace $(NAMESPACE) -f values.yaml \
		--set-string global.opensearch.password="$$OS_PW" \
		--set-string langflow.auth.secretKey="$$(openssl rand -hex 32)" \
		--set-string langflow.auth.superuserPassword="$$LF_PW" \
		--set-string backend.auth.sessionSecret="$$(openssl rand -hex 32)" \
		--set-string backend.encryption.key="$$(openssl rand -base64 32)" \
		-s templates/backend/backend-dotenv.yaml \
		-s templates/langflow/langflow-dotenv.yaml \
		-s templates/secrets/opensearch-secret.yaml \
		| sed -E "s|^( +SESSION_SECRET=).*|\\1\"$$(openssl rand -hex 32)\"|" \
		| oc apply -n $(NAMESPACE) -f -

clean:
	rm -rf vendor
