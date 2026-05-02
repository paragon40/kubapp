#!/usr/bin/env bash
set -euo pipefail

ENV="${{ env.ENV }}"
COMMIT="$(git rev-parse HEAD)"
TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

mkdir -p snapshot

jq -n \
  --arg env "$ENV" \
  --arg commit "$COMMIT" \
  --arg time "$TIME" \
  '{
    env: $env,
    commit: $commit,
    time: $time
  }' > snapshot/state.json

echo "✅ Snapshot created"
cat snapshot/state.json

jq -n \
  --arg env "$ENV" \
  --arg commit "$COMMIT" \
  --arg time "$TIME" \
  --arg services "$(find gitops/registry/$ENV -name '*.json' | wc -l)" \
  '{
    env: $env,
    commit: $commit,
    time: $time,
    service_count: $services
  }'


