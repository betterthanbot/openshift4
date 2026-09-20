ROCKETCHAT_VERSION := 7.0.2

all: repo fetch template

repo:
	helm repo add rocketchat 'https://rocketchat.github.io/helm-charts'
	helm repo update

fetch:
	rm -rf vendor/ && \
	helm fetch \
		--untar \
		--untardir vendor/ \
		rocketchat/rocketchat --version=$(ROCKETCHAT_VERSION)

template:
	helm template \
		rocketchat \
		--namespace=rocket-chat \
		--values=./values.yaml \
		vendor/rocketchat \
		> rocketchat.yaml
