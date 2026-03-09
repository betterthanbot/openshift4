fetch:
	vendir sync -f vendir.yml

template:
	helm template \
		litemaas \
		--namespace=litemaas \
		--values=./values.yaml \
		vendor \
		> litemaas.yaml