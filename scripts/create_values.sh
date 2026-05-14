#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# STATIC VALUES BUILDER
# =========================================================

ARTIFACT_FILE="${1:-}"
ROLE_ARN="${IRSA_ARN:-}"
SERVICE_TYPE="${SERVICE_TYPE:-}"
REPLICA_COUNT="${REPLICA_COUNT:-2}"
HPA_ENABLED="${HPA_ENABLED:-false}"

fail() {
  echo "❌ $1"
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

[[ -n "$ARTIFACT_FILE" ]] || fail "Usage: create_values.sh <artifact-json>"
[[ -f "$ARTIFACT_FILE" ]] || fail "Artifact not found: $ARTIFACT_FILE"

SVC_TYPE=$(jq -r '.type' "$ARTIFACT_FILE")
[[ "$SERVICE_TYPE" == "App" && "$SVC_TYPE" == "$SERVICE_TYPE" ]] || fail "Service Type Not found OR Doesnt Match: $SERVICE_TYPE != $SVC_TYPE"

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
TMP_VOL=$(jq -r '.tmp_volume // ""' "$ARTIFACT_FILE")
MNT_VOL=$(jq -r '.mount_vol // ""' "$ARTIFACT_FILE")
MNT_PATH=$(jq -r '.mount_path // ""' "$ARTIFACT_FILE")
VOLUMES_ENABLED=$(jq -r '.volumes_enabled // false' "$ARTIFACT_FILE")
TMP_ENABLED=$(jq -r '.tmp_enabled // false' "$ARTIFACT_FILE")
SVC_MONITOR_ENAB=$(jq -r '.svc_monitor_enabled // false' "$ARTIFACT_FILE")
NO_SECRETS=$(jq -r '.NO_SECRETS // ""' "$ARTIFACT_FILE")
SECRET_NAME="${SERVICE}-secrets"
COMPUTE_TYPE=$(jq -r '.computeType // "fargate"' "$ARTIFACT_FILE")

if [[ "$COMPUTE_TYPE" != "fargate" && "$COMPUTE_TYPE" != "node" ]]; then
  if [[ "$COMPUTE_TYPE" != "ec2" ]]; then
    fail "❌ Invalid COMPUTE_TYPE: $COMPUTE_TYPE (must be fargate or node)"
  if
fi

ARR=("SERVICE" "ENV" "NAMESPACE" "ROLE_ARN" "PORT" "IMAGE" "TAG" "CONTAINER_UID" "HEALTH" "LIVE" "TMP_ENABLED" "VOLUMES_ENABLED" "SVC_MONITOR_ENAB")
for var in "${ARR[@]}"; do
  value="${!var}"

  if [[ -z "$value" ]]; then
    echo "❌ $var required"
    exit 1
  fi

  export "$var=$value"
done

TARGET_DIR="gitops/envs/$ENV/apps/$SERVICE"
TARGET_FILE="$TARGET_DIR/values.yaml"

mkdir -p "$TARGET_DIR"

echo " Building static values for $SERVICE with $COMPUTE_TYPE"

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

serviceAccount:
  create: true
  name: ${SERVICE}-sa
  roleArn: $ROLE_ARN

serviceMonitor:
  enabled: $SVC_MONITOR_ENAB
  path: /metrics
  interval: 30s

replicaCount: $REPLICA_COUNT

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
    memory: 128Mi
  limits:
    cpu: 300m
    memory: 256Mi

env: {}

securityContext:
  pod:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault

  container:
    runAsNonRoot: true
    runAsUser: ${CONTAINER_UID}
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL

probes:
  readiness:
    httpGet:
      path: ${HEALTH}
      port: ${PORT}
    initialDelaySeconds: 5
    periodSeconds: 10

  liveness:
    httpGet:
      path: ${LIVE}
      port: ${PORT}
    initialDelaySeconds: 10
    periodSeconds: 15

  startup:
    httpGet:
      path: ${HEALTH}
      port: ${PORT}
    failureThreshold: 30
    periodSeconds: 5

hpa:
  enabled: $HPA_ENABLED
  minReplicas: 2
  maxReplicas: 4
  cpu: 70
  memory: 70

meta:
  staticFingerprint: $STATIC_FP
  generatedAt: $DATE
  source: build-pipeline
EOF

echo "Checks for $SERVICE volume config.."
echo "tmp_enabled: $TMP_ENABLED"
echo "vol_enabled: $VOLUMES_ENABLED"
echo "Temp Vol: $TMP_VOL"
echo "Mount Vol: $MNT_VOL"
echo "Mount Path: $MNT_PATH"

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

if [[ "$NO_SECRETS" == "false" && -n "$SECRET_NAME" && "$SECRET_NAME" != "null" ]]; then
cat >> /tmp/static-values.yaml <<EOF
secret:
  enabled: true
  name: $SECRET_NAME
EOF
fi

if [[ "$COMPUTE_TYPE" == "fargate" ]]; then
cat >> /tmp/static-values.yaml <<EOF

labels:
  compute: fargate
EOF
fi

if [[ "$COMPUTE_TYPE" == "node" ]]; then
cat >> /tmp/static-values.yaml <<EOF

nodeSelector:
  compute: ec2

tolerations:
  - key: compute
    operator: Equal
    value: ec2
    effect: NoSchedule
EOF
fi

####################################################
# APPLY STRATEGY (SAFE + IDENTITY PRESERVING)
####################################################
if [[ -f "$TARGET_FILE" ]]; then
  echo " Merging existing values.yaml"

  # safer merge: preserve runtime-managed sections
  yq eval-all '
    select(fileIndex == 0) * select(fileIndex == 1) |
    . as $item ireduce ({}; . *+ $item)
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
