#!/usr/bin/env bash
set -euo pipefail

BASE_URL="http://localhost:3000/webhook/github"
REPO="codest/kubapp"

echo "Generating synthetic GitHub events..."

# ------------------------------------------------------------
# Push events
# ------------------------------------------------------------
for i in {1..5}; do
  curl -s -X POST "$BASE_URL" \
    -H "X-GitHub-Event: push" \
    -H "Content-Type: application/json" \
    -d "{
      \"repository\": {\"full_name\": \"$REPO\"},
      \"after\": \"commit-$i\"
    }" >/dev/null
done

# ------------------------------------------------------------
# Pull request events
# ------------------------------------------------------------
for action in opened synchronize closed; do
  curl -s -X POST "$BASE_URL" \
    -H "X-GitHub-Event: pull_request" \
    -H "Content-Type: application/json" \
    -d "{
      \"repository\": {\"full_name\": \"$REPO\"},
      \"action\": \"$action\"
    }" >/dev/null
done

# ------------------------------------------------------------
# Workflow runs
# ------------------------------------------------------------
for conclusion in success failure success success; do
  START=$(date -u -d '2 minutes ago' +"%Y-%m-%dT%H:%M:%SZ")
  END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  curl -s -X POST "$BASE_URL" \
    -H "X-GitHub-Event: workflow_run" \
    -H "Content-Type: application/json" \
    -d "{
      \"repository\": {\"full_name\": \"$REPO\"},
      \"workflow_run\": {
        \"name\": \"CI Pipeline\",
        \"status\": \"completed\",
        \"conclusion\": \"$conclusion\",
        \"run_started_at\": \"$START\",
        \"updated_at\": \"$END\"
      }
    }" >/dev/null
done

# ------------------------------------------------------------
# Release
# ------------------------------------------------------------
curl -s -X POST "$BASE_URL" \
  -H "X-GitHub-Event: release" \
  -H "Content-Type: application/json" \
  -d "{
    \"repository\": {\"full_name\": \"$REPO\"},
    \"release\": {
      \"tag_name\": \"v1.0.0\"
    }
  }" >/dev/null

# ------------------------------------------------------------
# Issues
# ------------------------------------------------------------
for action in opened closed reopened; do
  STATE="open"
  [[ "$action" == "closed" ]] && STATE="closed"

  curl -s -X POST "$BASE_URL" \
    -H "X-GitHub-Event: issues" \
    -H "Content-Type: application/json" \
    -d "{
      \"repository\": {\"full_name\": \"$REPO\"},
      \"action\": \"$action\",
      \"issue\": {
        \"state\": \"$STATE\"
      }
    }" >/dev/null
done

echo "Test data generated successfully..."

