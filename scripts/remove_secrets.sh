#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=================================================="
echo "[INFO] SAFE SECRET CLEANUP STARTED"
echo "[INFO] ROOT: $ROOT_DIR"
echo "=================================================="

echo
echo "[WARN] This will delete ONLY:"
echo "  - iac/**/*.enc"
echo "  - docker/**/secrets.yml"
echo "  - gitops/secrets/*.yml|*.yaml"
echo
read -rp "Type 'YES' to continue: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
  echo "[INFO] Aborted"
  exit 0
fi

############################################
# 1. DELETE .enc ONLY IN iac/
############################################

echo
echo "[INFO] Removing .enc files inside iac/ only..."

find "$ROOT_DIR/iac" \
  -type f \
  -name "*.enc" \
  -print -delete

############################################
# 2. REMOVE DOCKER SECRETS FILES
############################################

echo
echo "[INFO] Removing docker secrets.yml..."

find "$ROOT_DIR/docker" \
  -type f \
  -name "secrets.yml" \
  -print -delete

############################################
# 3. REMOVE GITOPS SECRETS
############################################

echo
echo "[INFO] Removing gitops secrets..."

find "$ROOT_DIR/gitops/secrets" \
  -type f \( -name "*.yml" -o -name "*.yaml" \) \
  -print -delete

############################################
# 4. VERIFY .BAK SAFETY
############################################

echo
echo "[INFO] Checking .bak files (should NOT be touched)..."

BAK_COUNT=$(find "$ROOT_DIR" -type f -name "*.bak" | wc -l)

echo "[INFO] .bak files remaining: $BAK_COUNT"

############################################
# DONE
############################################

echo
echo "=================================================="
echo "[INFO] CLEANUP COMPLETE"
echo "=================================================="
