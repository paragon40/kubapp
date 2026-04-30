#!/bin/bash
set -euo pipefail

TARGET="gitops/registry"
TMP_DIR=$(mktemp -d)

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "🔍 Computing current hash..."

CURRENT_HASH=$(find "$TARGET" -type f -print0 2>/dev/null \
  | sort -z \
  | xargs -0 sha256sum 2>/dev/null \
  | sha256sum \
  | awk '{print $1}')

echo " Fetching remote state..."
git fetch origin main

echo "Extracting remote registry..."

if git ls-tree -r origin/main --name-only | grep -q "^$TARGET/"; then
  git archive origin/main "$TARGET" | tar -x -C "$TMP_DIR"

  REMOTE_HASH=$(find "$TMP_DIR/$TARGET" -type f -print0 \
    | sort -z \
    | xargs -0 sha256sum \
    | sha256sum \
    | awk '{print $1}')
else
  echo "⚠️ Remote registry not found — treating as empty"
  REMOTE_HASH="EMPTY"
fi

echo "Current: ${CURRENT_HASH:-EMPTY}"
echo "Remote : ${REMOTE_HASH:-EMPTY}"

if [[ "${CURRENT_HASH:-EMPTY}" == "${REMOTE_HASH:-EMPTY}" ]]; then
  echo "✅ NO CHANGE DETECTED"
  exit 0
fi

echo "⚠️ CHANGE DETECTED"

########################################
# SAFE COMMIT + PUSH (WITH REBASE)
########################################

git config user.name "github-actions"
git config user.email "github-actions@github.com"

git add "$TARGET"

if git diff --cached --quiet; then
  echo "No staged changes after all"
  exit 0
fi

git commit -m "[BUILD_APP (REGISTRY)] change detected via hash"

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

