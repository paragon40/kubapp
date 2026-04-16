#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR=${1:-artifacts}

echo "Validating GitOps V3 structure..."

FILES=$(find "$ARTIFACT_DIR" -name "*.json")

if [ -z "$FILES" ]; then
  echo "No artifacts found"
  exit 1
fi

for file in $FILES; do
  SERVICE=$(jq -r .service "$file")
  ENV=$(jq -r .env "$file")

  echo "Checking $SERVICE ($ENV)"

  # ------------------------
  # VALIDATE INPUT DATA
  # ------------------------
  if [ -z "$SERVICE" ] || [ "$SERVICE" = "null" ]; then
    echo "Invalid SERVICE in $file"
    exit 1
  fi

  if [ -z "$ENV" ] || [ "$ENV" = "null" ]; then
    echo "Invalid ENV in $file"
    exit 1
  fi

  # ------------------------
  # V3 STRUCTURE PATH
  # ------------------------
  VALUES_FILE="gitops/envs/$ENV/$SERVICE/values.yaml"

  echo "Checking path: $VALUES_FILE"

  # ------------------------
  # CHECK FILE EXISTENCE
  # ------------------------
  if [ ! -f "$VALUES_FILE" ]; then
    echo "Missing values.yaml: $VALUES_FILE"
    exit 1
  fi

  # ------------------------
  # YAML VALIDATION
  # ------------------------
  yq e '.' "$VALUES_FILE" >/dev/null || {
    echo "Invalid YAML: $VALUES_FILE"
    exit 1
  }

done

echo "All GitOps paths valid"

