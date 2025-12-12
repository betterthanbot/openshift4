# openshift4
## rhacs central
CENTRAL_CHART_VERSION="400.9.1"

helm pull rhacs/central-services \
    --version $CENTRAL_CHART_VERSION \
    --untar \
    --untardir central-services-$CENTRAL_CHART_VERSION

## rhacs secured-cluster-services
SECURED_CLUSTER_SERVICES_CHART_VERSION="74.9.0"

helm pull rhacs/central-services \
    --version $SECURED_CLUSTER_SERVICES_CHART_VERSION \
    --untar \
    --untardir central-services-$SECURED_CLUSTER_SERVICES_CHART_VERSION