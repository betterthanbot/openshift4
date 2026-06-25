CTFD_VERSION   := 2.0.0
CTFD_REPO_NAME := pascaliske
CTFD_REPO_URL  := https://charts.pascaliske.dev

all: repo fetch template

repo:
	helm repo add $(CTFD_REPO_NAME) $(CTFD_REPO_URL)
	helm repo update

fetch:
	rm -rf vendor/ && \
	helm fetch \
		--untar \
		--untardir vendor/ \
		$(CTFD_REPO_NAME)/ctfd --version=$(CTFD_VERSION)

template:
	helm template \
		ctfd \
		--namespace=ctfd \
		--values=./values.yaml \
		vendor/ctfd \
		> ctfd.yaml
