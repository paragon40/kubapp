#!/usr/bin/env bash
set -euo pipefail

ENV="${1:?ENV required}"
DOMAIN="${2:?DOMAIN required}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

ATTEMPTS=3
SLEEP=20
CANARY_REQUESTS=10
SUCCESS_THRESHOLD=90

echo "=================================="
echo " ADVANCED RUNTIME VERIFICATION (STABLE)"
echo "ENV: $ENV"
echo "DOMAIN: $DOMAIN"
echo "=================================="

SERVICES=$(find "$REG_DIR" -name "*.json" -exec jq -r '.service' {} \;)

declare -A RESULT

########################################
# SAFE HTTP CHECK
########################################
check_http() {
  local url="$1"

  [[ -z "$url" ]] && echo 0 && return

  local success=0
  local total=0

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$url" || echo "000")
    [[ "$code" == "200" ]] && success=$((success + 1))
    total=$((total + 1))
  done

  echo $(( success * 100 / total ))
}

########################################
# ROBUST POD HEALTH CHECK
########################################
check_pods() {
  local svc="$1"

  kubectl get pods -n "$ENV" --no-headers \
    | grep "$svc" \
    | awk '{print $3}' \
    | grep -Ev "Running|Completed" \
    || true
}

########################################
# SYNTHETIC TEST (SAFE DEFAULT)
########################################
synthetic_test() {
  local svc="$1"
  local url="https://${svc}.${DOMAIN}/health"

  curl -s --max-time 5 -o /dev/null -w "%{http_code}" "$url" | grep -q "200"
}

########################################
# ARGOCD WAIT WITH RETRY
########################################
wait_argocd() {
  local app="$1"

  for i in {1..3}; do
    if argocd app wait "$app" --sync --health --timeout 180; then
      return 0
    fi

    echo "⚠️ ArgoCD retry $i/3 for $app"
    sleep 10
  done

  return 1
}

########################################
# SERVICE CHECK
########################################
verify_service() {
  local svc="$1"
  local app="${svc}-${ENV}"
  local url="https://${svc}.${DOMAIN}"

  echo ""
  echo "=================================="
  echo " SERVICE: $svc"
  echo "=================================="

  RESULT["$svc"]="PASS"

  echo "[1/4] ArgoCD sync check..."
  if ! wait_argocd "$app"; then
    echo "❌ ArgoCD failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "[2/4] Kubernetes rollout..."
  if ! kubectl rollout status deploy/"$svc" -n "$ENV" --timeout=120s; then
    echo "❌ Rollout failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "[3/4] Pod health..."
  BAD=$(check_pods "$svc")

  if [[ -n "$BAD" ]]; then
    echo "❌ Unhealthy pods:"
    echo "$BAD"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "[4/5] Canary check..."
  PERCENT=$(check_http "$url")
  echo "Success rate: $PERCENT%"

  if (( PERCENT < SUCCESS_THRESHOLD )); then
    echo "❌ Canary failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "[5/5] Synthetic test..."
  if ! synthetic_test "$svc"; then
    echo "❌ Synthetic failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "✅ $svc PASSED"
}

########################################
# MAIN LOOP
########################################
for i in $(seq 1 "$ATTEMPTS"); do
  echo ""
  echo "=================================="
  echo " Iteration $i/$ATTEMPTS"
  echo "=================================="

  for svc in $SERVICES; do
    verify_service "$svc"
  done

  [[ $i -lt $ATTEMPTS ]] && sleep "$SLEEP"
done

########################################
# REPORT
########################################
echo ""
echo "=================================="
echo " FINAL REPORT"
echo "=================================="

FAILURES=0

for svc in $SERVICES; do
  status="${RESULT[$svc]:-UNKNOWN}"
  echo "$svc => $status"

  [[ "$status" != "PASS" ]] && ((FAILURES++))
done

echo ""

if [[ "$FAILURES" -gt 0 ]]; then
  echo "❌ SYSTEM NOT STABLE ($FAILURES failed)"
  exit 1
else
  echo "✅ SYSTEM VERIFIED"
fi
