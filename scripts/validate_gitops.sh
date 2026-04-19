#!/usr/bin/env bash
set -euo pipefail

APP_DIR="gitops/infra/apps"

echo "Validating ArgoCD Applications..."

fail() {
  echo "❌ $1"
  exit 1
}

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

  KIND=$(yq e '.kind' "$file")

  if [[ "$KIND" == "ApplicationSet" ]]; then
    PATH=$(yq e '.spec.template.spec.source.path' "$file")
  else
    PATH=$(yq e '.spec.source.path' "$file")
  fi

  NAME=$(yq e '.metadata.name' "$file")

  if [[ -z "$NAME" || "$NAME" == "null" ]]; then
    fail "Missing app name in $file"
  fi

  if [[ -z "$PATH" || "$PATH" == "null" ]]; then
    fail "Missing source path in $file"
  fi

  echo "✔ $NAME -> $PATH"

done

echo "All ArgoCD applications valid"
