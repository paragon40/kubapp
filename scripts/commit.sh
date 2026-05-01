#!/usr/bin/env bash
set -euo pipefail

TARGET="gitops/registry"
BRANCH="main"
STATE_FILE=${STATE_FILE:?Supply State File}

echo ""
echo "======================================"
echo "REGISTRY COMMIT PIPELINE"
echo "======================================"

########################################
# CONFIG
########################################
git config user.name "github-actions"
git config user.email "github-actions@github.com"

########################################
# ENSURE TARGET EXISTS
########################################
if [[ ! -d "$TARGET" ]]; then
  echo "⚠️ $TARGET does not exist — nothing to commit"
  exit 0
fi

########################################
# STAGE ONLY REGISTRY
########################################
echo " Staging registry + state file changes..."
git add "$STATE_FILE"
git add "$TARGET"

########################################
# CHECK IF ANY REAL CHANGE EXISTS
########################################
if git diff --cached --quiet; then
  echo "✅ No changes detected in $TARGET"
  exit 0
fi

echo "⚠️ Changes detected — preparing commit"

########################################
# OPTIONAL: SHOW WHAT CHANGED (DEBUG)
########################################
git status --short "$TARGET"

########################################
# COMMIT
########################################
git commit -m "[REGISTRY] update ($(date -u +'%Y-%m-%dT%H:%M:%SZ'))"

########################################
# SAFE PUSH (MULTI-WRITER SAFE)
########################################
echo "Pushing to $BRANCH (with rebase protection)..."

for i in {1..3}; do
  if git push origin HEAD:$BRANCH; then
    echo "✅ Push succeeded"
    exit 0
  fi

  echo "⚠️ Push failed (attempt $i) — resolving..."

  # Sync with remote
  git fetch origin "$BRANCH"
  git rebase "origin/$BRANCH"
done

echo "❌ Failed to push after retries"
exit 1
