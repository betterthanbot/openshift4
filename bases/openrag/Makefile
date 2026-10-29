OPENRAG_VERSION := 0.7.10
OPENRAG_CHART   := oci://ghcr.io/linagora/openrag-stack

all: fetch template

# vendor/ is gitignored (~27MB with subcharts) — only openrag.yaml is committed.
fetch:
	rm -rf vendor/ && \
	helm pull \
		--untar \
		--untardir vendor/ \
		$(OPENRAG_CHART) --version=$(OPENRAG_VERSION)

template:
	helm template \
		openrag \
		--namespace=openrag \
		--values=./values.yaml \
		vendor/openrag-stack \
		> openrag.yaml
