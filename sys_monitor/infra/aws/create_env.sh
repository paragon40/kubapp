#!/usr/bin/env bash
set -euo pipefail

# -------- INPUTS --------
MODE="${MODE:-local}"              # default to local if not set
ACCOUNT_ID="${ACCOUNT_ID:?ACCOUNT_ID is required}"  # must be provided

# Optional overrides (can also be exported before running)
TARGET_CLUSTER_NAME="${TARGET_CLUSTER_NAME:-kubapp-dev}"
TARGET_REGION="${TARGET_REGION:-us-east-1}"
AWS_REGION="${AWS_REGION:-us-east-1}"

ENV_FILE=".env"

echo "Generating $ENV_FILE ..."

# -------- LOGIC --------
if [[ "$MODE" == "cross" ]]; then
  CLUSTER_MODE="cross"
  TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/sys-monitor-cross-account-role"
else
  CLUSTER_MODE="local"
  TARGET_ROLE_ARN=""
fi

# -------- WRITE .ENV --------
cat > "$ENV_FILE" <<EOF
CLUSTER_MODE=${CLUSTER_MODE}
TARGET_ROLE_ARN=${TARGET_ROLE_ARN}
TARGET_CLUSTER_NAME=${TARGET_CLUSTER_NAME}
TARGET_REGION=${TARGET_REGION}
AWS_REGION=${AWS_REGION}
ACCOUNT_ID=${ACCOUNT_ID}
EOF

echo ".env generated successfully:"
cat "$ENV_FILE"
echo "=============================================="
