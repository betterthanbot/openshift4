KYVERNO_VERSION := 3.7.0
POLICY_VERSION := 3.7.2

all: repo fetch template
repoFetch: repo fetch
template: kyverno policy

repo:
	helm repo add \
		kyverno 'https://kyverno.github.io/kyverno/'
	helm repo update

	helm repo add \
		policy-reporter 'https://kyverno.github.io/policy-reporter/'
	helm repo update

fetch:
	rm -rf vendor/ && \
	helm fetch \
		--untar \
			--untardir vendor/ \
			kyverno/kyverno --version=$(KYVERNO_VERSION)

	helm fetch \
		--untar \
			--untardir vendor/ \
			policy-reporter/policy-reporter --version=$(POLICY_VERSION)

kyverno:
	helm template \
		kyverno \
		--namespace=kyverno \
		--values=./values.yaml \
		vendor/kyverno \
		> kyverno.yaml

policy:
	helm template \
		policy-reporter \
		--include-crds \
		--namespace=kyverno \
		--set metrics.enabled=true \
		--set rest.enabled=true \
		vendor/policy-reporter \
		> policy-reporter.yaml

skopeo:
	skopeo \
		--override-arch amd64 \
		--override-os linux \
		sync --scoped \
		--src yaml skopeo.yaml \
		--dest docker \
		--dest-tls-verify=false \
		quay.io/kyverno/
