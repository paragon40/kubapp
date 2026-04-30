#!/bin/bash
set -euo pipefail

TARGET="gitops/registry"

echo "🔍 Fetching remote state..."
git fetch origin main

echo "🔍 Computing tree hashes..."

LOCAL_HASH=$(git ls-tree -r HEAD "$TARGET" | sha256sum | awk '{print $1}' || echo "EMPTY")
REMOTE_HASH=$(git ls-tree -r origin/main "$TARGET" | sha256sum | awk '{print $1}' || echo "EMPTY")

echo "Local : $LOCAL_HASH"
echo "Remote: $REMOTE_HASH"

if [[ "$LOCAL_HASH" == "$REMOTE_HASH" ]]; then
  echo "✅ NO CHANGE DETECTED"
  exit 0
fi

echo "⚠️ CHANGE DETECTED"

########################################
# Now rely on Git for actual staging
########################################

git add "$TARGET"

if git diff --cached --quiet; then
  echo "⚠️ Hash changed but no actual Git diff — investigate normalization issue"
  exit 1
fi

echo "✅ Real changes confirmed — committing..."

git config user.name "github-actions"
git config user.email "github-actions@github.com"

git commit -m "[REGISTRY] update"

for i in {1..3}; do
  if git push origin HEAD:main; then
    echo "✅ Push succeeded"
    exit 0
  fi

  echo "⚠️ Push failed, retrying..."
  git fetch origin main
  git rebase origin/main
done

echo "❌ Failed to push after retries"
exit 1
