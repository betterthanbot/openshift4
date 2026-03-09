fetch:
	vendir sync -f vendir.yml

template:
	helm template \
		litemaas \
		--namespace=litemaas \
		--values=./values.yaml \
		--set global.platform=openshift \
		--set route.enabled=true \
		vendor \
		> litemaas.yaml