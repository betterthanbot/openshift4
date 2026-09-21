#! /bin/bash

num_args=1

if [ "$#" -ne $num_args ]
then
  echo "Error: Expected 1 argument"
  echo ""
  echo "Usage: getOCPSignature.sh 4.x.x"
  echo ""
  echo "Example: getOCPSignature.sh 4.19.4"
  exit 1
fi

OCP_RELEASE_NUMBER=$1
DIGEST_ALGO="sha256"
ARCHITECTURE=x86_64
REGISTRY="quay.io"
REPOSITORY="openshift-release-dev/ocp-release"
MIRROR_BASE="https://mirror.openshift.com/pub/openshift-v4/signatures/openshift/release"


DIGEST_HEADER=$(curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  "https://${REGISTRY}/v2/${REPOSITORY}/manifests/${OCP_RELEASE_NUMBER}-${ARCHITECTURE}" \
  | grep -i "^docker-content-digest:" | tr -d '\r')

if [ -z "$DIGEST_HEADER" ]; then
  echo "Error: Could not retrieve digest for tag '${OCP_RELEASE_NUMBER}'. Please check the version tag." >&2
  exit 1
fi

#get the hash
RAW_HASH=$(echo "$DIGEST_HEADER" | awk '{print $2}' | cut -d':' -f2)


#the DIGEST_ALGO-RAW_HASH combined should look something like this 
#sha256-29h3d92u3hd92u3r982u39r8293r8y239ry
#take note that it is '=' sign in the URL below
SIGNATURE_URL="${MIRROR_BASE}/${DIGEST_ALGO}=${RAW_HASH}/signature-1"
SIGNATURE_BASE64=$(curl -s ${SIGNATURE_URL} | base64 -w0 && echo)

#create the configmap yaml
cat > signature-${OCP_RELEASE_NUMBER}.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: release-image-${OCP_RELEASE_NUMBER}
  namespace: openshift-config-managed
  labels:
    release.openshift.io/verification-signatures: ""
binaryData:
  ${DIGEST_ALGO}-${RAW_HASH}: ${SIGNATURE_BASE64}
EOF

echo "File generated signature-${OCP_RELEASE_NUMBER}.yaml"