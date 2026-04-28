#!/usr/bin/env bash
set -euo pipefail

DIR="${1:-.}"
cd "$DIR"

echo "Running BACKEND drift check..."

STATE_BUCKET=$(terraform output -raw state_bucket_name 2>/dev/null || echo "")
LOCK_TABLE=$(terraform output -raw lock_table_name 2>/dev/null || echo "")

REGION=$(terraform output -raw region 2>/dev/null || echo "us-east-1")

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

DRIFT_FOUND=0
ISSUES=()

# ----------------------------
# 1. Check S3 bucket
# ----------------------------
if ! aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  DRIFT_FOUND=1
  ISSUES+=("s3_bucket_missing")
else
  echo "✅ S3 bucket exists"

  VERSIONING=$(aws s3api get-bucket-versioning \
    --bucket "$STATE_BUCKET" \
    --query "Status" --output text 2>/dev/null || echo "None")

  if [[ "$VERSIONING" != "Enabled" ]]; then
    DRIFT_FOUND=1
    ISSUES+=("s3_versioning_disabled")
  fi

  ENCRYPTION=$(aws s3api get-bucket-encryption \
    --bucket "$STATE_BUCKET" 2>/dev/null || true)

  if [[ -z "$ENCRYPTION" ]]; then
    DRIFT_FOUND=1
    ISSUES+=("s3_encryption_missing")
  fi
fi

# ----------------------------
# 2. Check DynamoDB lock table
# ----------------------------
if ! aws dynamodb describe-table --table-name "$LOCK_TABLE" >/dev/null 2>&1; then
  DRIFT_FOUND=1
  ISSUES+=("dynamodb_missing")
else
  echo "✅ DynamoDB table exists"

  KEY_SCHEMA=$(aws dynamodb describe-table \
    --table-name "$LOCK_TABLE" \
    --query "Table.KeySchema[0].AttributeName" \
    --output text)

  if [[ "$KEY_SCHEMA" != "LockID" ]]; then
    DRIFT_FOUND=1
    ISSUES+=("dynamodb_wrong_key")
  fi
fi

# ----------------------------
# 3. Logging (CloudWatch)
# ----------------------------
LOG_GROUP="/kubapp/boot/audit-logs"

if [[ $DRIFT_FOUND -eq 1 ]]; then
  echo "⚠️ Backend drift detected"

  aws logs put-log-events \
    --log-group-name "$LOG_GROUP" \
    --log-stream-name "backend-drift" \
    --log-events "timestamp=$(date +%s%3N),message={\"event\":\"backend_drift_detected\",\"bucket\":\"$STATE_BUCKET\",\"table\":\"$LOCK_TABLE\",\"issues\":$(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .),\"timestamp\":\"$TIMESTAMP\"}" \
    2>/dev/null || true

  exit 2
fi

echo "✅ Backend is clean"

aws logs put-log-events \
  --log-group-name "$LOG_GROUP" \
  --log-stream-name "backend-drift" \
  --log-events "timestamp=$(date +%s%3N),message={\"event\":\"backend_clean\",\"bucket\":\"$STATE_BUCKET\",\"table\":\"$LOCK_TABLE\",\"timestamp\":\"$TIMESTAMP\"}" \
  2>/dev/null || true

exit 0
