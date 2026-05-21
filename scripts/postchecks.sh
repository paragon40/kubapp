#!/usr/bin/env bash
set -euo pipefail

########################################
# INPUT VALIDATION
########################################
ENV="${1:?ENV required}"
DOMAIN="${2:?DOMAIN required}"

: "${ARGOCD_SERVER:?ARGOCD_SERVER not set}"
: "${ARGOCD_AUTH_TOKEN:?ARGOCD_AUTH_TOKEN not set}"

########################################
# OPTIONAL CONFIG (override via env if needed)
########################################
SUCCESS_THRESHOLD="${SUCCESS_THRESHOLD:-90}"
ATTEMPTS="${ATTEMPTS:-3}"
SLEEP="${SLEEP:-20}"
CANARY_REQUESTS="${CANARY_REQUESTS:-10}"

# default health paths (IMPORTANT FIX)
declare -A HEALTH_PATHS=(
  [default]="/health"
  [urlshortener]="/api/health"
)

########################################
# PATHS
########################################
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

[[ -d "$REG_DIR" ]] || { echo "❌ Registry not found: $REG_DIR"; exit 1; }

########################################
# HEADER
########################################
echo "=================================="
echo " ADVANCED RUNTIME VERIFICATION"
echo "ENV: $ENV"
echo "DOMAIN: $DOMAIN"
echo "ARGOCD_SERVER: $ARGOCD_SERVER"
echo "=================================="

########################################
# SERVICE DISCOVERY
########################################
mapfile -t SERVICES < <(
  find "$REG_DIR" -name "*.json" -exec jq -r '.service' {} \; | sort -u
)

[[ ${#SERVICES[@]} -gt 0 ]] || {
  echo "❌ No services found"
  exit 1
}

declare -A RESULT
declare -A FAIL_REASON

########################################
# HELPERS
########################################
get_health_path() {
  local svc="$1"
  echo "${HEALTH_PATHS[$svc]:-${HEALTH_PATHS[default]}}"
}

########################################
# HTTP CHECK (CANARY)
########################################
check_http() {
  local url="$1"
  local success=0
  local total=0

  [[ -n "$url" ]] || { echo 0; return; }

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(curl -ksS --max-time 5 -o /dev/null -w "%{http_code}" "$url" || echo "000")
    [[ "$code" == "200" ]] && ((success++))
    ((total++))
  done

  echo $(( success * 100 / total ))
}

########################################
# POD HEALTH
########################################
check_pods() {
  local svc="$1"

  kubectl get pods -n "$ENV" --no-headers 2>/dev/null \
    | grep "$svc" \
    | awk '{print $3}' \
    | grep -Ev "Running|Completed" \
    || true
}

########################################
# SYNTHETIC TEST (FIXED)
########################################
synthetic_test() {
  local svc="$1"
  local path
  path="$(get_health_path "$svc")"

  local url="https://${svc}.${DOMAIN}${path}"

  code=$(curl -ksS --max-time 5 -o /dev/null -w "%{http_code}" "$url" || echo "000")
  [[ "$code" == "200" ]]
}

########################################
# ARGOCD WAIT (ROBUST)
########################################
wait_argocd() {
  local app="$1"

  for i in 1 2 3; do
    echo "   ArgoCD attempt $i/3"

    if argocd app wait "$app" \
      --server "$ARGOCD_SERVER" \
      --auth-token "$ARGOCD_AUTH_TOKEN" \
      --grpc-web \
      --sync \
      --health \
      --operation \
      --timeout 180; then
      return 0
    fi

    sleep 10
  done

  return 1
}

########################################
# ROLLOUT CHECK
########################################
check_rollout() {
  local svc="$1"

  if kubectl get deployment "$svc" -n "$ENV" >/dev/null 2>&1; then
    kubectl rollout status deployment/"$svc" -n "$ENV" --timeout=120s
    return
  fi

  if kubectl get statefulset "$svc" -n "$ENV" >/dev/null 2>&1; then
    kubectl rollout status statefulset/"$svc" -n "$ENV" --timeout=120s
    return
  fi

  echo "⚠️ No workload found for $svc"
}

########################################
# SERVICE VERIFICATION
########################################
verify_service() {
  local svc="$1"
  local app="${svc}-${ENV}"
  local url="https://${svc}.${DOMAIN}"

  echo
  echo "=================================="
  echo " SERVICE: $svc"
  echo "=================================="

  RESULT["$svc"]="PASS"
  FAIL_REASON["$svc"]=""

  ##################################
  echo "[1/5] ArgoCD sync check..."
  if ! wait_argocd "$app"; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="ArgoCD failed"
    return
  fi

  ##################################
  echo "[2/5] Kubernetes rollout..."
  if ! check_rollout "$svc"; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Rollout failed"
    return
  fi

  ##################################
  echo "[3/5] Pod health..."
  bad=$(check_pods "$svc")
  if [[ -n "$bad" ]]; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Unhealthy pods"
    return
  fi

  ##################################
  echo "[4/5] Canary HTTP check..."
  percent=$(check_http "$url")
  echo "Success rate: ${percent}%"

  if (( percent < SUCCESS_THRESHOLD )); then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Canary below threshold"
    return
  fi

  ##################################
  echo "[5/5] Synthetic health check..."
  if ! synthetic_test "$svc"; then
    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Synthetic endpoint failed"
    return
  fi

  echo "✅ $svc PASSED"
}

########################################
# MAIN LOOP
########################################
for i in $(seq 1 "$ATTEMPTS"); do
  echo
  echo "=================================="
  echo " Stability iteration $i/$ATTEMPTS"
  echo "=================================="

  for svc in "${SERVICES[@]}"; do
    RESULT["$svc"]="${RESULT[$svc]:-UNKNOWN}"
    verify_service "$svc"
  done

  [[ $i -lt $ATTEMPTS ]] && sleep "$SLEEP"
done

########################################
# FINAL REPORT (FIXED + GROUPED)
########################################
echo
echo "=================================="
echo "FINAL VERIFICATION REPORT"
echo "=================================="

PASS_LIST=()
FAIL_LIST=()

for svc in "${SERVICES[@]}"; do
  status="${RESULT[$svc]:-UNKNOWN}"
  reason="${FAIL_REASON[$svc]:-}"

  if [[ "$status" == "PASS" ]]; then
    PASS_LIST+=("$svc")
  else
    FAIL_LIST+=("$svc ($reason)")
  fi
done

echo ""
echo "PASS:"
for s in "${PASS_LIST[@]}"; do
  echo "  - $s"
done

echo ""
echo "FAIL:"
for s in "${FAIL_LIST[@]}"; do
  echo "  - $s"
done

echo ""

if (( ${#FAIL_LIST[@]} > 0 )); then
  echo "❌ SYSTEM NOT STABLE (${#FAIL_LIST[@]} failed)"
  exit 1
else
  echo "✅ SYSTEM VERIFIED (ALL SERVICES HEALTHY)"
fi
