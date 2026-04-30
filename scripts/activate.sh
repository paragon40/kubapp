#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"

echo "=============================="
echo "ACTIVATION PIPELINE"
echo "ENV: $ENV"
echo "=============================="

############################################
# 1. VALIDATION (STRICT)
############################################
echo "[ACTIVATE] RUNNING VALIDATE SCRIPT..."
./scripts/validate.sh "$ENV"

############################################
# 2. PRE-FLIGHT EXECUTION SCRIPTS
############################################
echo "[ACTIVATE] RUNNING ENCRYPT SECRETS SCRIPT..."

./scripts/encrypt_secrets.sh "$ENV"

echo "[ACTIVATE] RUNNING VALIDATE GITOPS SCRIPT..."
./scripts/validate_gitops.sh

############################################
# 3. GIT PUSH
############################################
read -rp "Push to GitHub? (yes/no): " CONFIRM

if [[ "$CONFIRM" == "yes" ]]; then
  git add .
  git commit -m "chore: activate pipeline for $ENV" || echo "No changes"
  git push
  echo "✅ Pushed to GitHub"
else
  echo "Skipped push"
fi

echo "=============================="
echo "✅ ACTIVATION COMPLETE"
echo "=============================="
