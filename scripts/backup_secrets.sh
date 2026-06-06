#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="${1:-dev}"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
WORKDIR="/tmp/paragon-backup-$TIMESTAMP"

S3_BUCKET="test-backup-bucket"
S3_PREFIX="paragon-secrets/$ENV"

mkdir -p "$WORKDIR"

echo "=================================================="
echo "[INFO] BACKUP STARTED"
echo "[INFO] TIMESTAMP: $TIMESTAMP"
echo "=================================================="

############################################
# BACKUP .bak FILES
############################################

echo
echo "[INFO] Collecting .bak files..."

find "$ROOT_DIR" \
  -type f \
  -name "*.bak" \
  -exec cp --parents {} "$WORKDIR" \;

############################################
# BACKUP TFVARS
############################################

echo
echo "[INFO] Collecting tfvars..."

find "$ROOT_DIR/iac" \
  -path "*/envs/*" \
  -type f \
  -name "*.tfvars" \
  -exec cp --parents {} "$WORKDIR" \;

############################################
# CREATE ARCHIVE
############################################

ARCHIVE="/tmp/paragon-backup-$TIMESTAMP.tar.gz"

tar -czf "$ARCHIVE" -C "$WORKDIR" .

echo "[INFO] Archive created:"
echo "$ARCHIVE"

############################################
# UPLOAD TO S3
############################################

aws s3 cp \
  "$ARCHIVE" \
  "s3://$S3_BUCKET/$S3_PREFIX/$TIMESTAMP.tar.gz"

echo "[INFO] Upload complete"

rm -rf "$WORKDIR"

echo
echo "=================================================="
echo "[INFO] BACKUP COMPLETE"
echo "=================================================="
