# ==============================================================================
# Gatus Discovery Job Image — CVE-minimised (UBI Micro Approach)
# Multi-stage build:
#   builder  — downloads binaries AND provisions a rootfs for the micro image
#   runtime  — ubi-micro (no package manager, gnupg2, or libarchive inside)
# ==============================================================================

# ── Stage 1: builder ──────────────────────────────────────────────────────────
FROM registry.redhat.io/ubi9/ubi-minimal@sha256:8d0a8fb39ec907e8ca62cdd24b62a63ca49a30fe465798a360741fde58437a23 AS builder

ARG OC_VERSION=4.20.20
ARG JQ_VERSION=1.8.1

# Install tools needed for downloading/extracting on the builder
RUN microdnf install -y --nodocs tar gzip

# Create directories for our runtime filesystem and satisfy microdnf requirements
RUN mkdir -p /mnt/rootfs/usr/local/bin \
             /mnt/rootfs/var/cache/dnf \
             /etc/dnf/vars

# Install ONLY bash and ca-certificates into the isolated rootfs.
# We explicitly map the config, repos, and vars back to the builder's host OS 
# to satisfy microdnf's strict installroot requirements.
RUN microdnf --installroot=/mnt/rootfs \
             --releasever=9 \
             --config=/etc/dnf/dnf.conf \
             --noplugins \
             --setopt=cachedir=/mnt/rootfs/var/cache/dnf \
             --setopt=reposdir=/etc/yum.repos.d \
             --setopt=varsdir=/etc/dnf/vars \
             --setopt=install_weak_deps=0 \
             install -y --nodocs bash ca-certificates \
    && rm -rf /mnt/rootfs/var/cache/dnf

# Download and place the oc CLI directly into the rootfs
RUN curl -fsSL \
      "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-${OC_VERSION}/openshift-client-linux.tar.gz" \
      -o /tmp/oc.tar.gz \
    && tar -xzf /tmp/oc.tar.gz -C /mnt/rootfs/usr/local/bin oc \
    && rm /tmp/oc.tar.gz

# Download and place the static jq binary directly into the rootfs
RUN curl -fsSL \
      "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
      -o /mnt/rootfs/usr/local/bin/jq \
    && chmod +x /mnt/rootfs/usr/local/bin/jq

# ── Stage 2: lean runtime image ──────────────────────────────────────────────
# ubi-micro has absolutely no package manager or related overhead
FROM registry.redhat.io/ubi9/ubi-micro:latest

# Copy the pre-assembled filesystem from the builder
COPY --from=builder /mnt/rootfs /

# Set OpenShift-friendly non-root user
USER 1001

ENTRYPOINT ["/bin/bash"]