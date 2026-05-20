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
# PATHS
########################################
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

if [[ ! -d "$REG_DIR" ]]; then
  echo "❌ Registry directory not found: $REG_DIR"
  exit 1
fi

########################################
# SETTINGS
########################################
ATTEMPTS=3
SLEEP=20
CANARY_REQUESTS=10
SUCCESS_THRESHOLD=90

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
  find "$REG_DIR" -name "*.json" \
    -exec jq -r '.service' {} \; \
    | sort -u
)

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "❌ No services found in $REG_DIR"
  exit 1
fi

declare -A RESULT

########################################
# HTTP CHECK
########################################
check_http() {
  local url="$1"
  local success=0
  local total=0
  local code

  [[ -z "$url" ]] && echo 0 && return

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(curl -ksS --max-time 5 \
      -o /dev/null \
      -w "%{http_code}" \
      "$url" || echo "000")

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

  kubectl get pods -n "$ENV" --no-headers \
    | grep "$svc" \
    | awk '{print $3}' \
    | grep -Ev 'Running|Completed' \
    || true
}

########################################
# SYNTHETIC TEST
########################################
synthetic_test() {
  local svc="$1"
  local url="https://${svc}.${DOMAIN}/health"
  local code

  code=$(curl -ksS --max-time 5 \
    -o /dev/null \
    -w "%{http_code}" \
    "$url" || echo "000")

  [[ "$code" == "200" ]]
}

########################################
# ARGOCD WAIT
########################################
wait_argocd() {
  local app="$1"
  local attempt

  for attempt in 1 2 3; do
    echo "   ArgoCD attempt $attempt/3"

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

    if [[ "$attempt" -lt 3 ]]; then
      sleep 10
    fi
  done

  return 1
}

########################################
# ROLLOUT CHECK
########################################
check_rollout() {
  local svc="$1"

  if kubectl get deployment "$svc" -n "$ENV" >/dev/null 2>&1; then
    kubectl rollout status deployment/"$svc" \
      -n "$ENV" \
      --timeout=120s
    return
  fi

  if kubectl get statefulset "$svc" -n "$ENV" >/dev/null 2>&1; then
    kubectl rollout status statefulset/"$svc" \
      -n "$ENV" \
      --timeout=120s
    return
  fi

  echo "⚠️ No Deployment or StatefulSet named $svc found"
}

########################################
# SERVICE VERIFICATION
########################################
verify_service() {
  local svc="$1"
  local app="${svc}-${ENV}"
  local url="https://${svc}.${DOMAIN}"
  local bad
  local percent

  echo
  echo "=================================="
  echo " SERVICE: $svc"
  echo "=================================="

  RESULT["$svc"]="PASS"

  ##################################
  # 1. ArgoCD
  ##################################
  echo "[1/5] ArgoCD sync check..."
  if ! wait_argocd "$app"; then
    echo "❌ ArgoCD verification failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # 2. Rollout
  ##################################
  echo "[2/5] Kubernetes rollout..."
  if ! check_rollout "$svc"; then
    echo "❌ Rollout failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # 3. Pod Health
  ##################################
  echo "[3/5] Pod health..."
  bad=$(check_pods "$svc")

  if [[ -n "$bad" ]]; then
    echo "❌ Unhealthy pods detected:"
    echo "$bad"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # 4. Canary
  ##################################
  echo "[4/5] Canary HTTP check..."
  percent=$(check_http "$url")
  echo "Success rate: ${percent}%"

  if (( percent < SUCCESS_THRESHOLD )); then
    echo "❌ Canary threshold failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  ##################################
  # 5. Synthetic
  ##################################
  echo "[5/5] Synthetic health check..."
  if ! synthetic_test "$svc"; then
    echo "❌ Synthetic test failed"
    RESULT["$svc"]="FAIL"
    return
  fi

  echo "✅ $svc PASSED"
}

########################################
# MAIN LOOP
########################################
for iteration in $(seq 1 "$ATTEMPTS"); do
  echo
  echo "=================================="
  echo " Stability iteration $iteration/$ATTEMPTS"
  echo "=================================="

  for svc in "${SERVICES[@]}"; do
    verify_service "$svc"
  done

  if [[ "$iteration" -lt "$ATTEMPTS" ]]; then
    sleep "$SLEEP"
  fi
done

########################################
# FINAL REPORT
########################################
echo
echo "=================================="
echo "FINAL VERIFICATION REPORT"
echo "=================================="

FAILURES=0

for svc in "${SERVICES[@]}"; do
  status="${RESULT[$svc]:-UNKNOWN}"
  echo "$svc => $status"

  if [[ "$status" != "PASS" ]]; then
    ((FAILURES++))
  fi
done

echo
if (( FAILURES > 0 )); then
  echo "❌ SYSTEM NOT STABLE ($FAILURES services failed)"
  exit 1
else
  echo "✅ SYSTEM VERIFIED (ALL SERVICES HEALTHY)"
fi
