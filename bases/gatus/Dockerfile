# ==============================================================================
# Gatus Discovery Job Image
# Base: Red Hat UBI 9 minimal (supported, small, OpenShift-compatible)
# Includes: oc (OpenShift CLI), jq, bash, curl, ca-certificates
# ==============================================================================
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Install jq and other essentials via microdnf
RUN microdnf install -y \
      bash \
      ca-certificates \
      tar \
      gzip \
      jq \
    && microdnf clean all

# Install the OpenShift CLI (oc) — pinned to a stable release.
# Update OC_VERSION to match your cluster version (oc version --short).
ARG OC_VERSION=4.20
RUN curl -fsSL \
      "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OC_VERSION}/openshift-client-linux.tar.gz" \
      -o /tmp/oc.tar.gz \
    && tar -xzf /tmp/oc.tar.gz -C /usr/local/bin oc kubectl \
    && rm /tmp/oc.tar.gz \
    && oc version --client

# Smoke-test both tools are on PATH
RUN oc version --client && jq --version

# Run as non-root (good practice; OpenShift enforces this by default)
USER 1001

ENTRYPOINT ["/bin/bash"]