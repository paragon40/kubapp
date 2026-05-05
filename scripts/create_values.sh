#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# STATIC VALUES BUILDER (GITOPS SAFE)
# =========================================================

ARTIFACT_FILE="${1:-}"

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
IMAGE=$(jq -r '.image' "$ARTIFACT_FILE")
TAG=$(jq -r '.tag' "$ARTIFACT_FILE")
CONTAINER_UID=$(jq -r '.containerUid // 10001' "$ARTIFACT_FILE")
HEALTH=$(jq -r '.healthPath // "/health"' "$ARTIFACT_FILE")
LIVE=$(jq -r '.livePath // "/live"' "$ARTIFACT_FILE")
BASE=$(jq -r '.basePath // ""' "$ARTIFACT_FILE")
TMP_VOL=$(jq -r '.temp_vol // ""' "$ARTIFACT_FILE")
MNT_VOL=$(jq -r '.mount_vol // ""' "$ARTIFACT_FILE")
MNT_PATH=$(jq -r '.mount_path // ""' "$ARTIFACT_FILE")
VOLUMES_ENABLED=$(jq -r '.volumes_enabled // false' "$ARTIFACT_FILE")
TMP_ENABLED=$(jq -r '.tmp_enabled // false' "$ARTIFACT_FILE")

[[ -n "$SERVICE" && "$SERVICE" != "null" ]] || fail "Missing service"
[[ -n "$ENV" && "$ENV" != "null" ]] || fail "Missing env"
[[ -n "$NAMESPACE" && "$NAMESPACE" != "null" ]] || fail "Missing namespace"
[[ -n "$PORT" && "$PORT" != "null" ]] || fail "Missing port"
[[ -n "$IMAGE" && "$IMAGE" != "null" ]] || fail "Missing image"
[[ -n "$TAG" && "$TAG" != "null" ]] || fail "Missing tag"

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
    path: ${HEALTH}
    initialDelaySeconds: 5
    periodSeconds: 10

  liveness:
    path: ${LIVE}
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

if [[ "$TMP_ENABLED" == "true" && -n "$TMP_VOL" && -n "$MNT_VOL" && -n "$MNT_PATH" ]]; then
cat >> /tmp/static-values.yaml <<EOF

storage:
  volumes:
    - name: ${TMP_VOL}
      emptyDir: {}

  volumeMounts:
    - name: ${MNT_VOL}
      mountPath: ${MNT_PATH}
EOF
fi

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
