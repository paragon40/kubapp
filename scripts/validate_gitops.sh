#!/usr/bin/env bash
set -euo pipefail

APP_DIR="gitops/argocd"

echo "Validating ArgoCD Applications..."

############################################
# HELPERS
############################################
fail() {
  echo "❌ $1"
  exit 1
}

check_dir() {
  [[ -d "$1" ]] || fail "Missing directory: $1"
}

############################################
# VALIDATE APP DIR
############################################
check_dir "$APP_DIR"

############################################
# COLLECT FILES
############################################
mapfile -t FILES < <(
  find "$APP_DIR" \( -name "*.yml" -o -name "*.yaml" \)
)

if [[ ${#FILES[@]} -eq 0 ]]; then
  fail "No ArgoCD apps found in $APP_DIR"
fi

############################################
# VALIDATION LOOP
############################################
for file in "${FILES[@]}"; do
  echo "Checking $file"

  # YAML validation
  yq e '.' "$file" >/dev/null || fail "Invalid YAML: $file"

  KIND=$(yq e '.kind' "$file")
  NAME=$(yq e '.metadata.name' "$file")

  ############################################
  # Extract source safely (Helm OR Kustomize)
  ############################################
  if [[ "$KIND" == "ApplicationSet" ]]; then
    SOURCE_PATH=$(yq e '.spec.template.spec.source.path // ""' "$file")
    CHART=$(yq e '.spec.template.spec.source.chart // ""' "$file")
  else
    SOURCE_PATH=$(yq e '.spec.source.path // ""' "$file")
    CHART=$(yq e '.spec.source.chart // ""' "$file")
  fi

  ############################################
  # Basic validations
  ############################################
  if [[ -z "$NAME" || "$NAME" == "null" ]]; then
    fail "Missing app name in $file"
  fi

  ############################################
  # ENSURE SOURCE EXISTS
  ############################################
  if [[ -z "$SOURCE_PATH" && -z "$CHART" ]]; then
    fail "Missing source definition (neither path nor chart) in $file"
  fi

  ############################################
  # PREVENT INVALID MIXING
  ############################################
  if [[ -n "$SOURCE_PATH" && -n "$CHART" ]]; then
    fail "Invalid config in $file: cannot use BOTH chart and path"
  fi

  ############################################
  # OUTPUT RESULT
  ############################################
  if [[ -n "$CHART" ]]; then
    echo "✔ $NAME -> HELM chart: $CHART"
  else
    echo "✔ $NAME -> KUSTOMIZE path: $SOURCE_PATH"
  fi

done

echo "✅ All ArgoCD applications valid"
