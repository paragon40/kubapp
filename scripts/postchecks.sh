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
# OPTIONAL CONFIG
########################################
SUCCESS_THRESHOLD="${SUCCESS_THRESHOLD:-90}"
ATTEMPTS="${ATTEMPTS:-3}"
SLEEP="${SLEEP:-20}"
CANARY_REQUESTS="${CANARY_REQUESTS:-10}"

########################################
# PATHS
########################################
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REG_DIR="$ROOT/gitops/registry/$ENV"

[[ -d "$REG_DIR" ]] || {
  echo "❌ Registry not found: $REG_DIR"
  exit 1
}

########################################
# HEADER
########################################
echo "=================================="
echo "RUNTIME VERIFICATION"
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

[[ ${#SERVICES[@]} -gt 0 ]] || {
  echo "❌ No services found"
  exit 1
}

########################################
# STATE
########################################
declare -A RESULT
declare -A FAIL_REASON
declare -A SERVICE_FILES

########################################
# PRELOAD SERVICE -> FILE MAP
########################################
while IFS= read -r file; do
  svc="$(jq -r '.service' "$file" 2>/dev/null || true)"

  if [[ -n "$svc" && "$svc" != "null" ]]; then
    SERVICE_FILES["$svc"]="$file"
  fi
done < <(find "$REG_DIR" -name "*.json")

########################################
# HELPERS
########################################
get_service_file() {
  local svc="$1"

  echo "${SERVICE_FILES[$svc]:-}"
}

get_health_path() {
  local svc="$1"
  local file
  local path

  file="$(get_service_file "$svc")"

  if [[ -z "$file" ]]; then
    echo "/health"
    return
  fi

  path="$(jq -r '.healthPath' "$file" 2>/dev/null || true)"

  if [[ -n "$path" && "$path" != "null" ]]; then
    echo "$path"
  else
    echo "/health"
  fi
}

get_base_path() {
  local svc="$1"
  local file
  local path

  file="$(get_service_file "$svc")"

  if [[ -z "$file" ]]; then
    echo "/"
    return
  fi

  path="$(jq -r '.basePath' "$file" 2>/dev/null || true)"

  if [[ -n "$path" && "$path" != "null" ]]; then
    echo "$path"
  else
    echo "/"
  fi
}

########################################
# HTTP CANARY CHECK
########################################
check_http() {
  local url="$1"
  local success=0
  local total=0
  local code

  [[ -n "$url" ]] || {
    echo 0
    return
  }

  for _ in $(seq 1 "$CANARY_REQUESTS"); do
    code=$(curl -ksS \
      --max-time 5 \
      -o /dev/null \
      -w "%{http_code}" \
      "$url" || echo "000")

    if [[ "$code" =~ ^2 ]]; then
      ((success++))
    fi

    ((total++))
  done

  echo $(( success * 100 / total ))
}

########################################
# POD HEALTH CHECK
########################################
check_pods() {
  local svc="$1"

  kubectl get pods -n "$ENV" --no-headers 2>/dev/null \
    | grep "^${svc}-" \
    | awk '{print $2 " " $3}' \
    | grep -Ev '^[0-9]+/[0-9]+ Running|Completed' \
    || true
}

########################################
# SYNTHETIC HEALTH CHECK
########################################
synthetic_test() {
  local svc="$1"
  local path
  local url
  local code

  path="$(get_health_path "$svc")"
  url="https://${svc}.${DOMAIN}${path}"

  echo "Health URL: $url"

  code=$(curl -ksS \
    --max-time 5 \
    -o /dev/null \
    -w "%{http_code}" \
    "$url" || echo "000")

  [[ "$code" =~ ^2 ]]
}

########################################
# ARGOCD WAIT
########################################
wait_argocd() {
  local app="$1"
  local output

  for i in 1 2 3; do
    echo "   ArgoCD attempt $i/3"

    output=$(
      argocd app wait "$app" \
        --server "$ARGOCD_SERVER" \
        --auth-token "$ARGOCD_AUTH_TOKEN" \
        --grpc-web \
        --sync \
        --health \
        --operation \
        --timeout 180 \
        2>&1
    ) && return 0

    echo "$output"

    if echo "$output" | grep -qi "PermissionDenied"; then
      return 2
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

  echo "⚠️ No workload found for $svc"
}

########################################
# SERVICE VERIFICATION
########################################
verify_service() {
  local svc="$1"
  local app="${svc}-${ENV}"
  local base_path
  local url
  local bad
  local percent
  local argocd_result

  base_path="$(get_base_path "$svc")"
  url="https://${svc}.${DOMAIN}${base_path}"

  echo
  echo "=================================="
  echo "SERVICE: $svc"
  echo "=================================="

  RESULT["$svc"]="VERIFYING"
  FAIL_REASON["$svc"]=""

  ##################################
  echo "[1/5] ArgoCD sync check..."

  if wait_argocd "$app"; then
    :
  else
    argocd_result=$?

    if [[ "$argocd_result" -eq 2 ]]; then
      RESULT["$svc"]="FAIL"
      FAIL_REASON["$svc"]="ArgoCD permission denied"
    else
      RESULT["$svc"]="FAIL"
      FAIL_REASON["$svc"]="ArgoCD sync failed"
    fi

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

  bad="$(check_pods "$svc")"

  if [[ -n "$bad" ]]; then
    echo "$bad"

    RESULT["$svc"]="FAIL"
    FAIL_REASON["$svc"]="Unhealthy pods"
    return
  fi

  ##################################
  echo "[4/5] Canary HTTP check..."

  percent="$(check_http "$url")"

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

  RESULT["$svc"]="PASS"

  echo "✅ $svc PASSED"
}

########################################
# PHASE 1 — CONVERGENCE
########################################
PENDING_SERVICES=("${SERVICES[@]}")

for i in $(seq 1 "$ATTEMPTS"); do
  echo
  echo "=================================="
  echo "CONVERGENCE ITERATION $i/$ATTEMPTS"
  echo "=================================="

  NEXT_PENDING=()

  for svc in "${PENDING_SERVICES[@]}"; do
    verify_service "$svc"

    if [[ "${RESULT[$svc]}" != "PASS" ]]; then
      NEXT_PENDING+=("$svc")
    fi
  done

  ##################################
  # ITERATION SUMMARY
  ##################################
  echo
  echo "PASSED SO FAR:"

  for svc in "${SERVICES[@]}"; do
    if [[ "${RESULT[$svc]:-}" == "PASS" ]]; then
      echo "  - $svc"
    fi
  done

  echo
  echo "REMAINING:"

  if [[ ${#NEXT_PENDING[@]} -eq 0 ]]; then
    echo "  - none"
  else
    for svc in "${NEXT_PENDING[@]}"; do
      echo "  - $svc"
    done
  fi

  ##################################
  # ALL PASSED
  ##################################
  if [[ ${#NEXT_PENDING[@]} -eq 0 ]]; then
    echo
    echo "✅ All services passed convergence phase"
    break
  fi

  PENDING_SERVICES=("${NEXT_PENDING[@]}")

  [[ $i -lt "$ATTEMPTS" ]] && sleep "$SLEEP"
done

########################################
# PHASE 2 — STABILITY VALIDATION
########################################
if [[ ${#PENDING_SERVICES[@]} -eq 0 ]]; then
  echo
  echo "=================================="
  echo "STABILITY VALIDATION"
  echo "=================================="

  for svc in "${SERVICES[@]}"; do
    echo
    echo "Re-validating stable service: $svc"

    verify_service "$svc"

    if [[ "${RESULT[$svc]}" != "PASS" ]]; then
      FAIL_REASON["$svc"]="Failed stability recheck"
    fi
  done
else
  echo
  echo "❌ Stability validation skipped because some services never converged"
fi

########################################
# FINAL REPORT
########################################
echo
echo "=================================="
echo "FINAL VERIFICATION REPORT"
echo "=================================="

PASS_LIST=()
FAIL_LIST=()
UNKNOWN_LIST=()

for svc in "${SERVICES[@]}"; do
  status="${RESULT[$svc]:-UNKNOWN}"
  reason="${FAIL_REASON[$svc]:-}"

  case "$status" in
    PASS)
      PASS_LIST+=("$svc")
      ;;
    FAIL)
      FAIL_LIST+=("$svc ($reason)")
      ;;
    *)
      UNKNOWN_LIST+=("$svc")
      ;;
  esac
done

echo
echo "PASS:"
if [[ ${#PASS_LIST[@]} -eq 0 ]]; then
  echo "  - none"
else
  for s in "${PASS_LIST[@]}"; do
    echo "  - $s"
  done
fi

echo
echo "FAIL:"
if [[ ${#FAIL_LIST[@]} -eq 0 ]]; then
  echo "  - none"
else
  for s in "${FAIL_LIST[@]}"; do
    echo "  - $s"
  done
fi

echo
echo "UNKNOWN:"
if [[ ${#UNKNOWN_LIST[@]} -eq 0 ]]; then
  echo "  - none"
else
  for s in "${UNKNOWN_LIST[@]}"; do
    echo "  - $s"
  done
fi

echo

if (( ${#FAIL_LIST[@]} > 0 || ${#UNKNOWN_LIST[@]} > 0 )); then
  echo "❌ SYSTEM NOT STABLE"
  exit 1
else
  echo "✅ SYSTEM VERIFIED (ALL SERVICES HEALTHY)"
fi
