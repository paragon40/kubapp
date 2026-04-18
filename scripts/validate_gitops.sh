#!/usr/bin/env bash
set -euo pipefail

APP_DIR="gitops/infra/apps"

echo "Validating ArgoCD Applications..."

FILES=$(find "$APP_DIR" -name "*.yml" -o -name "*.yaml")

if [ -z "$FILES" ]; then
  echo "No ArgoCD apps found"
  exit 1
fi

for file in $FILES; do
  echo "Checking $file"

  # validate YAML
  yq e '.' "$file" >/dev/null || {
    echo "❌ Invalid YAML: $file"
    exit 1
  }

  # check required fields
  NAME=$(yq e '.metadata.name' "$file")
  PATH=$(yq e '.spec.source.path' "$file")

  if [ -z "$NAME" ] || [ "$NAME" = "null" ]; then
    echo "❌ Missing app name in $file"
    exit 1
  fi

  if [ -z "$PATH" ] || [ "$PATH" = "null" ]; then
    echo "❌ Missing Helm path in $file"
    exit 1
  fi

  echo "✔ $NAME -> $PATH"
done

echo "All ArgoCD applications valid"
