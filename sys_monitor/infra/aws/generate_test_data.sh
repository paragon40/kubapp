#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_URL="http://3.216.132.162:3000/webhook/github"

LINE="============================================================"

echo "$LINE"
echo "Generating synthetic GitHub webhook traffic"
echo "$LINE"

# ------------------------------------------------------------
# PUSH EVENTS
# ------------------------------------------------------------
for i in {1..5}; do
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: push" \
    -d "{
      \"repository\": {\"full_name\": \"paragon40/kubapp\"},
      \"after\": \"commit-$i\"
    }" > /dev/null
done

echo "Generated 5 push events"

# ------------------------------------------------------------
# PR EVENTS
# ------------------------------------------------------------
for action in opened synchronize closed; do
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: pull_request" \
    -d "{
      \"action\": \"$action\",
      \"repository\": {\"full_name\": \"paragon40/kubapp\"}
    }" > /dev/null
done

echo "Generated 3 PR events"

# ------------------------------------------------------------
# ISSUE EVENTS
# ------------------------------------------------------------
for state in open closed; do
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: issues" \
    -d "{
      \"action\": \"updated\",
      \"issue\": {\"state\": \"$state\"},
      \"repository\": {\"full_name\": \"paragon40/kubapp\"}
    }" > /dev/null
done

echo "Generated 2 issue events"

# ------------------------------------------------------------
# WORKFLOW SUCCESSES
# ------------------------------------------------------------
for i in {1..8}; do
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: workflow_run" \
    -d "{
      \"repository\": {\"full_name\": \"paragon40/kubapp\"},
      \"workflow_run\": {
        \"name\": \"CI Pipeline\",
        \"status\": \"completed\",
        \"conclusion\": \"success\"
      }
    }" > /dev/null
done

echo "Generated 8 successful workflow runs"

# ------------------------------------------------------------
# WORKFLOW FAILURES
# ------------------------------------------------------------
for i in {1..2}; do
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: workflow_run" \
    -d "{
      \"repository\": {\"full_name\": \"paragon40/kubapp\"},
      \"workflow_run\": {
        \"name\": \"CI Pipeline\",
        \"status\": \"completed\",
        \"conclusion\": \"failure\"
      }
    }" > /dev/null
done

echo "Generated 2 failed workflow runs"

echo "$LINE"
echo "Synthetic data generation complete"
echo "$LINE"
echo "Expected results:"
echo "  Workflow success rate: 80%"
echo "  SLO target:            95%"
echo "  Burn rate:             4.0"
echo "  Health score:          reduced"
echo "  Anomaly flag:          1"
echo "$LINE"
echo "Grafana:    http://3.216.132.162:3001"
echo "Prometheus: http://3.216.132.162:9090"
echo "$LINE"
