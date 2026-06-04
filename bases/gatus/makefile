.PHONY: gatus vendor

vendor:
	vendir sync

gatus:
	helm template \
		gatus \
		./vendor/gatus-helmchart \
		> gatus.yaml