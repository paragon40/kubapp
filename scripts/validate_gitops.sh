#!/usr/bin/env bash
set -euo pipefail

echo "Starting full GitOps validation..."

############################################
# DIRECTORIES (FULL SYSTEM COVERAGE)
############################################
DIRS=(
  "gitops/argocd"
  "gitops/envs"
  "gitops/ingress"
  "gitops/charts"
)

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

check_yaml() {
  local file="$1"
  yq e '.' "$file" >/dev/null 2>&1 || fail "Invalid YAML: $file"
}

if ! command -v yq >/dev/null 2>&1; then
  fail "yq is required but not installed"
fi

############################################
# VALIDATE CORE STRUCTURE
############################################
for dir in "${DIRS[@]}"; do
  echo ""
  echo "Checking directory: $dir"
  check_dir "$dir"

  mapfile -t FILES < <(
    find "$dir" \( -name "*.yml" -o -name "*.yaml" \)
  )

  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "⚠️  No YAML files found in $dir"
    continue
  fi

  ############################################
  # FILE VALIDATION LOOP
  ############################################
  for file in "${FILES[@]}"; do
    echo " Validating: $file"

    # basic YAML check
    if [[ "$file" == *"/templates/"* ]]; then
      echo "Skipping raw YAML validation for Helm template"
    else
      check_yaml "$file"
    fi

    ############################################
    # ARGOCD VALIDATION
    ############################################
    if [[ "$dir" == "gitops/argocd" ]]; then
      KIND=$(yq e '.kind' "$file")
      NAME=$(yq e '.metadata.name' "$file")

      [[ "$NAME" != "null" && -n "$NAME" ]] || fail "Missing metadata.name in $file"

      if [[ "$KIND" == "ApplicationSet" || "$KIND" == "Application" ]]; then
        echo "✔ ArgoCD object: $KIND ($NAME)"
      else
        fail "Invalid ArgoCD kind in $file: $KIND"
      fi
    fi

    ############################################
    # ENV VALIDATION (values.yaml)
    ############################################
    if [[ "$dir" == "gitops/envs" ]]; then
      APP_NAME=$(yq e '.appName' "$file")
      NAMESPACE=$(yq e '.namespace' "$file")
      IMAGE=$(yq e '.image.repository' "$file")

      [[ -n "$APP_NAME" && "$APP_NAME" != "null" ]] || fail "Missing appName in $file"
      [[ -n "$NAMESPACE" && "$NAMESPACE" != "null" ]] || fail "Missing namespace in $file"
      [[ -n "$IMAGE" && "$IMAGE" != "null" ]] || fail "Missing image.repository in $file"

      echo "✔ App env config: $APP_NAME ($NAMESPACE)"
    fi

    ############################################
    # INGRESS VALIDATION
    ############################################
    if [[ "$dir" == "gitops/ingress" ]]; then
      INGRESS_NAME=$(yq e '.ingress.name' "$file")
      SERVICES_COUNT=$(yq e '.services | length' "$file")

      [[ -n "$INGRESS_NAME" && "$INGRESS_NAME" != "null" ]] || fail "Missing ingress.name in $file"
      [[ "$SERVICES_COUNT" -ge 0 ]] || fail "Invalid services list in $file"

      echo "✔ Ingress: $INGRESS_NAME (services: $SERVICES_COUNT)"
    fi
  done
done

echo ""

if command -v helm >/dev/null 2>&1; then
  echo "⎈ Validating Helm charts..."

  for chart in gitops/charts/*; do
    [[ -d "$chart" ]] || continue

    if [[ -f "$chart/Chart.yaml" ]]; then
      echo "Checking Helm chart: $chart"

      helm template test "$chart" >/dev/null 2>&1 \
        || fail "Helm template validation failed: $chart"

      echo "✔ Helm chart valid: $chart"
    fi
  done

else
  if [[ "${CI:-}" == "true" ]]; then
    fail "helm is required in CI but not installed"
  else
    echo "⚠️  Helm not installed locally — skipping Helm chart validation"
  fi
fi

echo ""
echo "✅ Full GitOps validation successful"
