#!/usr/bin/env bash
set -euo pipefail

ENV="${1:?ENV required}"
DOMAIN="${2:?DOMAIN required}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

echo "=================================="
echo "🚀 ADVANCED RUNTIME VERIFICATION"
echo "ENV: $ENV"
echo "DOMAIN: $DOMAIN"
echo "=================================="

SERVICES=$(find "$REG_DIR" -name "*.json" -exec jq -r '.service' {} \;)

########################################
# CONFIGURABLE THRESHOLDS
########################################
ATTEMPTS=3
SLEEP=20

SUCCESS_THRESHOLD=90   # % success required
CANARY_REQUESTS=10     # requests per service

########################################
# FUNCTION: HTTP CHECK WITH METRICS
########################################
check_http() {
  local url=$1

  success=0
  total=0

  for i in $(seq 1 $CANARY_REQUESTS); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

    if [[ "$code" == "200" ]]; then
      success=$((success+1))
    fi

    total=$((total+1))
  done

  percent=$((success * 100 / total))
  echo "$percent"
}

########################################
# FUNCTION: SYNTHETIC TEST (example)
########################################
synthetic_test() {
  local svc=$1
  local url="https://$svc.$DOMAIN/health"

  echo "🔬 Synthetic test: $svc"

  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")

  if [[ "$code" != "200" ]]; then
    echo "❌ Synthetic check failed for $svc"
    return 1
  fi

  return 0
}

########################################
# STABILITY LOOP
########################################
for i in $(seq 1 $ATTEMPTS); do
  echo ""
  echo "🔁 Stability iteration $i/$ATTEMPTS"
  echo "----------------------------------"

  for svc in $SERVICES; do
    APP="${svc}-${ENV}"
    URL="https://$svc.$DOMAIN"

    echo ""
    echo "🔍 Checking service: $svc"

    ##################################
    # ArgoCD
    ##################################
    argocd app wait "$APP" \
      --sync \
      --health \
      --timeout 180

    ##################################
    # Kubernetes rollout
    ##################################
    kubectl rollout status deploy/"$svc" -n "$ENV" --timeout=120s

    ##################################
    # Pod health
    ##################################
    BAD=$(kubectl get pods -n "$ENV" \
      --no-headers | grep "$svc" | grep -v Running || true)

    if [[ -n "$BAD" ]]; then
      echo "❌ Pod instability detected"
      echo "$BAD"
      exit 1
    fi

    ##################################
    # CANARY TRAFFIC TEST
    ##################################
    echo "🐤 Canary testing: $URL"

    PERCENT=$(check_http "$URL")

    echo "Success rate: $PERCENT%"

    if (( PERCENT < SUCCESS_THRESHOLD )); then
      echo "❌ Canary threshold failed ($PERCENT% < $SUCCESS_THRESHOLD%)"
      exit 1
    fi

    ##################################
    # SYNTHETIC TEST
    ##################################
    synthetic_test "$svc" || exit 1

    echo "✅ $svc passed all checks"
  done

  ##################################
  # WAIT BETWEEN ITERATIONS
  ##################################
  if [[ "$i" -lt "$ATTEMPTS" ]]; then
    echo "⏳ Waiting $SLEEP sec..."
    sleep "$SLEEP"
  fi
done

echo ""
echo "✅ SYSTEM VERIFIED (STABLE + HEALTHY)"

check_slo() {
  local svc=$1

  # Example placeholder
  ERROR_RATE=$(curl -s "http://prometheus/api/v1/query?query=error_rate{$svc}" | jq -r '.data.result[0].value[1]')

  echo "SLO error rate for $svc: $ERROR_RATE"

  MAX_ERROR=0.05

  awk "BEGIN {exit !($ERROR_RATE < $MAX_ERROR)}" || {
    echo "❌ SLO violation for $svc"
    exit 1
  }
}


