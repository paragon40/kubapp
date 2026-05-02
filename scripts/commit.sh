#!/usr/bin/env bash
set -euo pipefail

BRANCH="main"

echo ""
echo "======================================"
echo "COMMIT PIPELINE"
echo "======================================"

########################################
# CONFIG
########################################
git config user.name "github-actions"
git config user.email "github-actions@github.com"

########################################
# INPUT VALIDATION
########################################
[[ $# -gt 0 ]] || {
  echo "❌ Usage: commit.sh <file_or_dir...> [commit_message]"
  exit 1
}

TS=$(date +'%Y-%m-%d %H:%M:%S')

########################################
# ROOT DETECTION (CI + LOCAL SAFE)
########################################
if [[ "${CI:-false}" == "true" || "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  LOC="CI"
  ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null)

  [[ -n "$ROOT_DIR" ]] || {
    echo "❌ CI mode but not inside a git repo"
    exit 1
  }

else
  LOC="LOCAL"
  ROOT_DIR=$(git rev-parse --show-toplevel 2>/dev/null || true)

  if [[ -z "$ROOT_DIR" ]]; then
    ROOT_DIR="$(pwd)"
  fi
fi

cd "$ROOT_DIR"

########################################
# ARGUMENT PARSING (STRICT POSITIONAL RULE)
########################################
ARGS=("$@")
LAST="${ARGS[-1]}"

HAS_MESSAGE=false

# message only if:
# - more than 1 arg
# - last arg is NOT a path
if [[ $# -gt 1 ]]; then
  if [[ ! -e "$LAST" && "$LAST" != */* ]]; then
    HAS_MESSAGE=true
  fi
fi

if [[ "$HAS_MESSAGE" == "true" ]]; then
  COMMIT_MSG_RAW="$LAST"
  PATHS=("${ARGS[@]:0:${#ARGS[@]}-1}")
else
  COMMIT_MSG_RAW="Auto Commit Update"
  PATHS=("${ARGS[@]}")
fi

COMMIT_MSG="[$TS] $COMMIT_MSG_RAW ($LOC)"

########################################
# STAGE ONLY PROVIDED PATHS
########################################
echo "Staging selected paths..."

for p in "${PATHS[@]}"; do
  git add "$p"
done

########################################
# CHECK FOR REAL CHANGES
########################################
if git diff --cached --quiet; then
  echo "✅ No changes detected"
  exit 0
fi

echo "⚠️ Changes detected — preparing commit"

git status --short

########################################
# COMMIT
########################################
git commit -m "$COMMIT_MSG"

########################################
# SAFE PUSH (REBASE PROTECTED)
########################################
echo "Pushing to $BRANCH (with rebase protection)..."

for i in {1..3}; do
  if git push origin HEAD:$BRANCH; then
    echo "✅ Push succeeded"
    exit 0
  fi

  echo "⚠️ Push failed (attempt $i) — resolving..."

  git fetch origin "$BRANCH"
  git rebase "origin/$BRANCH"
done

echo "❌ Failed to push after retries"
exit 1
