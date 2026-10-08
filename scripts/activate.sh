#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"
PUSH="${PUSH:-false}"
PUSH="${PUSH,,}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi

source "$ROOT/reuse.sh"
source "$ROOT/scripts/extra/git_functions.sh"

echo "=============================="
echo "ACTIVATION PIPELINE"
echo "ENV: $ENV"
echo "ROOT: $ROOT"
echo "=============================="

############################################
# 1. GIT PREPARATION
############################################
echo "--------------------------------------------------"
echo "[INFO] PREPARING GIT STATE"
echo "--------------------------------------------------"

apply_git rebase prepare

############################################
# 2. VALIDATION
############################################
echo "[ACTIVATE] RUNNING VALIDATE SCRIPT..."
./scripts/extra/validate.sh "$ENV"

############################################
# 3. PRE-FLIGHT EXECUTION SCRIPTS
############################################
echo "[ACTIVATE] RUNNING ENCRYPT SECRETS SCRIPT..."
./scripts/extra/encrypt_secrets.sh "$ENV"

echo "[ACTIVATE] RUNNING VALIDATE GITOPS SCRIPT..."
./scripts/gitops/validate_gitops.sh

############################################
# 4. GIT FINALIZATION
############################################
echo "--------------------------------------------------"
echo "[INFO] GIT OPERATIONS"
echo "--------------------------------------------------"

End() {
    echo "====================================================="
    echo "✅ ACTIVATION COMPLETE: $(date '+%Y-%m-%d_%H:%M:%S')"
    echo "====================================================="
    exit 0
}

if [[ "${PUSH,,}" != "true" && "${PUSH,,}" != "yes" ]]; then
    read -rp "Push to GitHub? (yes/no): " CONFIRM

    if [[ "${CONFIRM,,}" != "yes" ]]; then
        echo "[WARN] ⚠️ Push skipped by user"
        End
    fi
fi

COMMIT_MSG="[CHORE (Activate)]: run activation pipeline for $ENV - $(date '+%Y-%m-%d %H:%M:%S')"
apply_git rebase finalize "$COMMIT_MSG"
End
