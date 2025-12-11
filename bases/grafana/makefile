helm: add fetch deployment

HELM_CHART_NAME := stackrox/
HELM_CHART_SECURE_CLUSTER := stackrox-secured-cluster-services
HELM_CHART_CENTRAL_SERVICE := stackrox-central-services
HELM_CHART_VERSION := 400.9.1

add:
	helm repo add stackrox https://raw.githubusercontent.com/stackrox/helm-charts/main/opensource/ \
	helm repo update

fetch1:
	helm fetch \
		$(HELM_CHART_NAME)$(HELM_CHART_SECURE_CLUSTER) \
		--version $(HELM_CHART_VERSION) \
		--untar \
		--untardir vendor/$(HELM_CHART_VERSION)

fetch2:
	helm fetch \
		$(HELM_CHART_NAME)$(HELM_CHART_CENTRAL_SERVICE) \
		--version $(HELM_CHART_VERSION) \
		--untar \
		--untardir vendor/$(HELM_CHART_VERSION)

deployment1:
	helm template $(HELM_CHART_SECURE_CLUSTER) \
	--namespace=stackrox \
	--values=secure-cluster-values.yaml \
	--set clusterName=test \
    --set centralEndpoint=test \
	vendor/$(HELM_CHART_VERSION)/$(HELM_CHART_SECURE_CLUSTER) > $(HELM_CHART_VERSION)-$(HELM_CHART_SECURE_CLUSTER)-deployment.yaml

deployment2:
	helm template $(HELM_CHART_CENTRAL_SERVICE) \
	--namespace=stackrox \
	--values=central-services-values.yaml \
	--set clusterName=test \
    --set centralEndpoint=test \
	vendor/$(HELM_CHART_VERSION)/$(HELM_CHART_CENTRAL_SERVICE) > $(HELM_CHART_VERSION)-$(HELM_CHART_CENTRAL_SERVICE)-deployment.yaml