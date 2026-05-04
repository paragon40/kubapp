#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# STATIC VALUES BUILDER (GITOPS SAFE)
# =========================================================

ARTIFACT_FILE="${1:-}"
CONTAINER_UID="${CONTAINER_UID:-10001}"
URL_HEALTH="${URL_HEALTH:-/health}"
URL_LIVE="${URL_LIVE:-/live}"

fail() {
  echo "❌ $1"
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

[[ -n "$ARTIFACT_FILE" ]] || fail "Usage: create_values.sh <artifact-json>"
[[ -f "$ARTIFACT_FILE" ]] || fail "Artifact not found: $ARTIFACT_FILE"

require jq
require yq

SERVICE=$(jq -r '.service' "$ARTIFACT_FILE")
ENV=$(jq -r '.env' "$ARTIFACT_FILE")
NAMESPACE=$(jq -r '.namespace' "$ARTIFACT_FILE")
PORT=$(jq -r '.port' "$ARTIFACT_FILE")

[[ -n "$SERVICE" && "$SERVICE" != "null" ]] || fail "Missing service"
[[ -n "$ENV" && "$ENV" != "null" ]] || fail "Missing env"
[[ -n "$NAMESPACE" && "$NAMESPACE" != "null" ]] || fail "Missing namespace"
[[ -n "$PORT" && "$PORT" != "null" ]] || fail "Missing port"

TARGET_DIR="gitops/envs/$ENV/$SERVICE"
TARGET_FILE="$TARGET_DIR/values.yaml"

mkdir -p "$TARGET_DIR"

echo " Building static values for $SERVICE"

####################################################
# STATIC FINGERPRINT (NO IMAGE DEPENDENCY)
####################################################
STATIC_FP=$(echo -n "$SERVICE|$NAMESPACE|$PORT|v1" | sha256sum | awk '{print $1}')

DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

####################################################
# BASE STRUCTURE
####################################################
cat > /tmp/static-values.yaml <<EOF
appName: $SERVICE
namespace: $NAMESPACE

replicaCount: 2

image:
  repository: $(jq -r '.image' "$ARTIFACT_FILE")
  tag: $(jq -r '.tag' "$ARTIFACT_FILE")
  pullPolicy: Always

service:
  type: ClusterIP
  port: 80
  targetPort: $PORT

resources:
  requests:
    cpu: 100m
  limits:
    cpu: 300m

env: {}

securityContext:
  pod:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault

  container:
    runAsUser: ${CONTAINER_UID}
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

probes:
  readiness:
    path: ${URL_HEALTH}
    initialDelaySeconds: 5
    periodSeconds: 10

  liveness:
    path: ${URL_LIVE}
    initialDelaySeconds: 10
    periodSeconds: 15

hpa:
  enabled: false
  minReplicas: 1
  maxReplicas: 2
  cpu: 70

meta:
  staticFingerprint: $STATIC_FP
  generatedAt: $DATE
  source: build-pipeline
EOF

####################################################
# APPLY STRATEGY (SAFE + IDENTITY PRESERVING)
####################################################
if [[ -f "$TARGET_FILE" ]]; then
  echo " Merging existing values.yaml"

  # safer merge: preserve runtime-managed sections
  yq eval-all '
    select(fileIndex == 0) * select(fileIndex == 1)
  ' "$TARGET_FILE" /tmp/static-values.yaml > /tmp/merged.yaml

  mv /tmp/merged.yaml "$TARGET_FILE"
else
  echo " Creating values.yaml"
  mv /tmp/static-values.yaml "$TARGET_FILE"
fi

####################################################
# ENSURE FINGERPRINT IS ALWAYS CONSISTENT
####################################################
yq e -i ".meta.staticFingerprint = \"$STATIC_FP\"" "$TARGET_FILE"

echo "✅ Static values ready: $TARGET_FILE"
