#!/usr/bin/env bash
set -uo pipefail

ENV="${1:?ENV required}"
DOMAIN="${2:?DOMAIN required}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

ATTEMPTS=3
SLEEP=20
CANARY_REQUESTS=10
SUCCESS_THRESHOLD=90

echo "=================================="
echo "🚀 ADVANCED RUNTIME VERIFICATION (UPGRADED)"
echo "ENV: $ENV"
echo "DOMAIN: $DOMAIN"
echo "=================================="

# Collect services
SERVICES=$(find "$REG_DIR" -name "*.json" -exec jq -r '.service' {} \;)

# Store results
declare -A RESULT

########################################
# HTTP CANARY TEST
########################################
check_http() {
  local url="$1"

  if [[ -z "$url" || "$url" == "true" ]]; then
    echo "0"
    return
  fi

  local success=0
  local total=0

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

    [[ "$code" == "200" ]] && success=$((success + 1))
    total=$((total + 1))
  done

  echo $(( success * 100 / total ))
}

########################################
# SYNTHETIC TEST
########################################
synthetic_test() {
  local svc="$1"
  local url="https://${svc}.${DOMAIN}/health"

  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

  [[ "$code" == "200" ]]
}

########################################
# SERVICE VERIFICATION
########################################
verify_service() {
  local svc="$1"
  local app="${svc}-${ENV}"
  local url="https://${svc}.${DOMAIN}"

  echo ""
  echo "=================================="
  echo "🔎 SERVICE: $svc"
  echo "=================================="

  RESULT["$svc"]="PASS"

  ##################################
  # ArgoCD
  ##################################
  echo "[1/4] ArgoCD sync check..."

  if ! argocd app wait "$app" --sync --health --timeout 180; then
    echo "❌ ArgoCD failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # Rollout
  ##################################
  echo "[2/4] Kubernetes rollout..."

  if ! kubectl rollout status deploy/"$svc" -n "$ENV" --timeout=120s; then
    echo "❌ Rollout failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # Pod health
  ##################################
  echo "[3/4] Pod health check..."

  BAD=$(kubectl get pods -n "$ENV" --no-headers | grep "$svc" | grep -v Running || true)

  if [[ -n "$BAD" ]]; then
    echo "❌ Unhealthy pods detected"
    echo "$BAD"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # Canary
  ##################################
  echo "[4/5] Canary HTTP check..."

  PERCENT=$(check_http "$url")
  echo "Success rate: $PERCENT%"

  if (( PERCENT < SUCCESS_THRESHOLD )); then
    echo "❌ Canary threshold failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # Synthetic test
  ##################################
  echo "[5/5] Synthetic health check..."

  if ! synthetic_test "$svc"; then
    echo "❌ Synthetic test failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "✅ $svc PASSED all checks"
}

########################################
# MAIN LOOP (NO EARLY EXIT)
########################################
for i in $(seq 1 "$ATTEMPTS"); do
  echo ""
  echo "=================================="
  echo "🔁 Stability iteration $i/$ATTEMPTS"
  echo "=================================="

  for svc in $SERVICES; do
    verify_service "$svc"
  done

  [[ $i -lt $ATTEMPTS ]] && sleep "$SLEEP"
done

########################################
# FINAL REPORT
########################################
echo ""
echo "=================================="
echo "📊 FINAL VERIFICATION REPORT"
echo "=================================="

FAILURES=0

for svc in $SERVICES; do
  status="${RESULT[$svc]}"

  [[ -z "$status" ]] && status="UNKNOWN"

  echo "$svc => $status"

  if [[ "$status" != "PASS" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
done

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "❌ SYSTEM NOT STABLE ($FAILURES services failed)"
  exit 1
else
  echo "✅ SYSTEM VERIFIED (ALL SERVICES HEALTHY)"
fi
