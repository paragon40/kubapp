#!/usr/bin/env bash
set -euo pipefail

ENV="${1:?ENV required}"
DOMAIN="${2:?DOMAIN required}"

: "${ARGOCD_SERVER:?ARGOCD_SERVER not set}"
: "${ARGOCD_AUTH_TOKEN:?ARGOCD_AUTH_TOKEN not set}"

SUCCESS_THRESHOLD="${SUCCESS_THRESHOLD:-90}"
ATTEMPTS="${ATTEMPTS:-3}"
SLEEP="${SLEEP:-20}"
CANARY_REQUESTS="${CANARY_REQUESTS:-10}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

[[ -d "$REG_DIR" ]] || { echo "❌ Registry not found: $REG_DIR"; exit 1; }

echo "=================================="
echo "RUNTIME VERIFICATION"
echo "ENV: $ENV"
echo "DOMAIN: $DOMAIN"
echo "=================================="

mapfile -t SERVICES < <(
  find "$REG_DIR" -name "*.json" -exec jq -r '.service' {} \; | sort -u
)

declare -A RESULT FAIL_REASON SERVICE_FILES

while IFS= read -r file; do
  svc="$(jq -r '.service' "$file" 2>/dev/null || true)"
  [[ -n "$svc" && "$svc" != "null" ]] && SERVICE_FILES["$svc"]="$file"
done < <(find "$REG_DIR" -name "*.json")

########################################
# HELPERS
########################################

get_file() { echo "${SERVICE_FILES[$1]:-}"; }

get_stack() {
  local f; f="$(get_file "$1")"
  [[ -z "$f" ]] && { echo "app"; return; }

  local v
  v="$(jq -r '.stack // empty' "$f")"
  [[ -n "$v" ]] && echo "$v" || echo "app"
}

get_argocd_app() {
  local svc="$1"
  local stack
  stack="$(get_stack "$svc")"

  # SYSTEM STACKS -> FIXED INFRA APPS
  case "$stack" in
    monitoring)
      echo "ingress-${ENV}-monitoring"
      ;;
    argocd)
      echo "ingress-${ENV}-argocd"
      ;;
    *)
      echo "${svc}-${ENV}"
      ;;
  esac
}

get_path() {
  local f; f="$(get_file "$1")"
  [[ -z "$f" ]] && { echo "/"; return; }

  jq -r '.basePath // "/"' "$f"
}

check_http() {
  local url="$1"
  local ok=0 total=0 code

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(curl -ksS --max-time 5 -o /dev/null -w "%{http_code}" "$url" || echo 000)
    [[ "$code" =~ ^2 ]] && ((ok++))
    ((total++))
  done

  echo $((ok * 100 / total))
}

check_pods() {
  kubectl get pods -n "$ENV" --no-headers 2>/dev/null | grep -v "Running" || true
}

synthetic_test() {
  local svc="$1"
  local f; f="$(get_file "$svc")"

  # ONLY FOR APP STACKS
  local stack
  stack="$(get_stack "$svc")"
  [[ "$stack" != "app" ]] && return 0

  local url="https://${svc}.${DOMAIN}$(jq -r '.healthPath // "/health"' "$f")"

  curl -ksS --max-time 5 -o /dev/null -w "%{http_code}" "$url" | grep -q "^2"
}

wait_argocd() {
  local app="$1"

  argocd app wait "$app" \
    --server "$ARGOCD_SERVER" \
    --auth-token "$ARGOCD_AUTH_TOKEN" \
    --grpc-web \
    --sync \
    --health \
    --operation \
    --timeout 180
}

verify_service() {
  local svc="$1"
  local stack app url base

  stack="$(get_stack "$svc")"
  app="$(get_argocd_app "$svc")"
  base="$(get_path "$svc")"
  url="https://${svc}.${DOMAIN}${base}"

  echo
  echo "SERVICE: $svc"
  echo "STACK: $stack"
  echo "ARGOCD APP: $app"

  RESULT["$svc"]="VERIFYING"

  ##################################
  echo "[1/5] ArgoCD sync check..."

  if [[ "$stack" == "app" ]]; then
    if ! wait_argocd "$app"; then
      RESULT["$svc"]="FAIL"
      FAIL_REASON["$svc"]="ArgoCD failed"
      return
    fi
  else
    echo "Skipping ArgoCD (system stack: $stack)"
    kubectl get pods -n "$stack" >/dev/null 2>&1 || true
  fi

  ##################################
  echo "[2/5] Pod health..."
  if [[ -n "$(check_pods)" ]]; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Pod issues"
    return
  fi

  ##################################
  echo "[3/5] Canary..."
  percent="$(check_http "$url")"
  echo "Success: $percent%"
  (( percent < SUCCESS_THRESHOLD )) && {
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Canary fail"
    return
  }

  ##################################
  echo "[4/5] Synthetic..."
  if ! synthetic_test "$svc"; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Synthetic fail"
    return
  fi

  RESULT["$svc"]="PASS"
  echo "✅ $svc OK"
}

########################################
# MAIN LOOP
########################################

PENDING=("${SERVICES[@]}")

for i in $(seq 1 "$ATTEMPTS"); do
  echo "=================================="
  echo "ITERATION $i/$ATTEMPTS"
  echo "=================================="

  NEXT=()

  for s in "${PENDING[@]}"; do
    verify_service "$s"
    [[ "${RESULT[$s]}" != "PASS" ]] && NEXT+=("$s")
  done

  [[ ${#NEXT[@]} -eq 0 ]] && break
  PENDING=("${NEXT[@]}")
  sleep "$SLEEP"
done

########################################
# REPORT
########################################

echo "=================================="
echo "FINAL REPORT"
echo "=================================="

for s in "${SERVICES[@]}"; do
  echo "$s -> ${RESULT[$s]:-UNKNOWN} (${FAIL_REASON[$s]:-})"
done

[[ ${#PENDING[@]} -gt 0 ]] && exit 1 || exit 0
