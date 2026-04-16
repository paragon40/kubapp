#!/usr/bin/env bash
set -euo pipefail

SERVICE=$1
FROM_ENV=$2
TO_ENV=$3

BASE_DIR="gitops/envs"

FROM_FILE="$BASE_DIR/$FROM_ENV/apps/$SERVICE/values.yaml"
TO_FILE="$BASE_DIR/$TO_ENV/apps/$SERVICE/values.yaml"

echo " Promoting $SERVICE from $FROM_ENV → $TO_ENV"

# -----------------------------
# VALIDATION
# -----------------------------
if [ ! -f "$FROM_FILE" ]; then
  echo "❌ Source values not found: $FROM_FILE"
  exit 1
fi

if [ ! -f "$TO_FILE" ]; then
  echo "Target missing, creating structure..."
  mkdir -p "$(dirname "$TO_FILE")"
  cp "$FROM_FILE" "$TO_FILE"
  echo "✅ Created new target env values"
  exit 0
fi

# -----------------------------
# COPY BASE CONFIG
# -----------------------------
cp "$FROM_FILE" "$TO_FILE"

# -----------------------------
# OPTIONAL: enforce production rules
# -----------------------------

# Example: force replica minimum in prod
if [ "$TO_ENV" = "prod" ]; then
  echo "Applying production safeguards"

  yq e '.replicas = (.replicas // 1 | if . < 2 then 2 else . end)' -i "$TO_FILE"

  # Example: ensure image is immutable tag only
  yq e '.image.pullPolicy = "IfNotPresent"' -i "$TO_FILE"
fi

echo "✅ Promotion complete: $SERVICE ($FROM_ENV → $TO_ENV)"
