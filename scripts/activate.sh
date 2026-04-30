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
echo "--------------------------------------------------"
echo "[INFO] GIT OPERATIONS"
echo "--------------------------------------------------"

read -rp "Push to GitHub? (yes/no): " CONFIRM

if [[ "$CONFIRM" == "yes" ]]; then
  echo "[INFO] Staging changes..."
  git add .

  COMMIT_MSG="[CHORE (Activate)]: run activation pipeline for $ENV - $(date '+%Y-%m-%d %H:%M:%S')"

  echo "[INFO] Creating commit..."
  git commit -m "$COMMIT_MSG" || echo "[WARN] ⚠️ No changes to commit"

  echo "[INFO] Pushing to remote..."
  if git push; then
  echo "[INFO] ✅ Push successful"
  else
    echo "[WARN] ⚠️  Remote State Changed, Rebasing First..."
    git pull --rebase && git push
    echo "[INFO] ✅ Push successful"
  fi
else
  echo "[WARN] ⚠️ Push skipped by user"
fi

echo "=============================="
echo "✅ ACTIVATION COMPLETE"
echo "=============================="
