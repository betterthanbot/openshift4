.PHONY: gatus
GATUS_VERSION := 5.35.0
GATUS_DISCOVERY_VERSION := 1.0.0

gatus:
	helm template \
		gatus \
		--values=./values.yaml \
		./ \
		> gatus.yaml

pull:
	podman pull --platform linux/amd64 twinproduction/gatus:$(GATUS_VERSION)
tag:
	podman tag twinproduction/gatus:$(GATUS_VERSION) quay.io/rhn-support-gong/gatus:$(GATUS_VERSION)
push:
	podman push quay.io/rhn-support-gong/gatus:$(GATUS_VERSION)

podman-build:
	podman build \
	--build-arg OC_VERSION=4.20 \
	--platform linux/amd64 \
	-t quay.io/rhn-support-gong/gatus-discovery:$(GATUS_DISCOVERY_VERSION) \
	-f Dockerfile .

podman-push:
	podman push quay.io/rhn-support-gong/gatus-discovery:$(GATUS_DISCOVERY_VERSION)