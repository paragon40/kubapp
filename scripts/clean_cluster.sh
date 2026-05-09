#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TF_CREATED_NS=${TF_CREATED_NS:-()}
eval "TF_CREATED_NS=$TF_CREATED_NS"

echo "======================================"
echo "  KUBERNETES RECONCILIATION CLEANER"
echo "======================================"

########################################
# SAFETY GUARD
########################################
CTX=$(kubectl config current-context || true)
if echo "$CTX" | grep -qi "prod"; then
  echo "❌ Refusing to run in prod context: $CTX"
  exit 1
fi

########################################
# HELPERS
########################################

sleep_safe() {
  sleep "${1:-3}"
}

count_resources() {
  kubectl get "$1" -n "$2" --no-headers 2>/dev/null | wc -l || true
}

patch_finalizers_ns() {
  local ns=$1
  echo ">> Removing namespace finalizers: $ns"
  kubectl patch ns "$ns" \
    -p '{"spec":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
}

patch_finalizers_objects() {
  local ns=$1
  local type=$2

  for obj in $(kubectl get "$type" -n "$ns" -o name 2>/dev/null || true); do
    kubectl patch "$obj" -n "$ns" \
      -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
  done
}

safe_delete_loop() {
  local ns=$1
  local type=$2
  local timeout=${3:-40}

  echo ">> Cleaning $type in $ns"

  SECONDS=0

  while true; do
    kubectl delete "$type" --all -n "$ns" --ignore-not-found >/dev/null 2>&1 || true
    sleep_safe 3

    remaining=$(count_resources "$type" "$ns")

    if [[ "$remaining" -eq 0 ]]; then
      echo "✅ $type cleaned in $ns"
      break
    fi

    echo "⚠️ $type still remaining in $ns: $remaining"

    if (( SECONDS > timeout )); then
      echo "Timeout reached for $type in $ns"

      echo ">> Inspecting stuck $type..."
      kubectl get "$type" -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true
      echo ""

      patch_finalizers_objects "$ns" "$type"

      echo ">> Retrying $type cleanup..."
      SECONDS=0
    fi

    sleep_safe 5
  done
}

########################################
# ARGOCD CLEANUP (ROOT CONTROLLERS FIRST)
########################################

echo ">> Deleting ArgoCD ApplicationSets..."
kubectl delete applicationsets.argoproj.io --all -n argocd --ignore-not-found || true

echo ">> Deleting ArgoCD Applications..."
kubectl delete applications.argoproj.io --all -n argocd --ignore-not-found || true

########################################
# NAMESPACE LOOP
########################################

ALL_NS=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')

for ns in $ALL_NS; do

  case "$ns" in
    kube-system|default|kube-public|kube-node-lease|argocd)
      echo "Skipping system namespace: $ns"
      continue
      ;;
  esac

  echo ""
  echo "=============================="
  echo " CLEANING NAMESPACE: $ns"
  echo "=============================="

  ########################################
  # RESOURCE CLEANUP LOOP
  ########################################

  safe_delete_loop "$ns" "all" 40
  safe_delete_loop "$ns" "ingress" 40
  safe_delete_loop "$ns" "svc" 30
  safe_delete_loop "$ns" "secret" 30
  safe_delete_loop "$ns" "pvc" 60

  for tf_ns in "${TF_CREATED_NS[@]}"; do
    if [[ "$ns" == "$tf_ns" ]]; then
      echo "Skipping Terraform-managed namespace: $ns"
      continue 2
    fi
  done

  ########################################
  # FINAL NAMESPACE DELETE LOOP
  ########################################

  echo ">> Deleting namespace: $ns"

  SECONDS=0

  kubectl delete ns "$ns" --ignore-not-found || true

  while kubectl get ns "$ns" >/dev/null 2>&1; do

    status=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)

    echo "⚠️ Namespace $ns still exists (status: $status)"

    if [[ "$status" == "Terminating" ]]; then
      patch_finalizers_ns "$ns"
    fi

    if (( SECONDS > 60 )); then
      echo "Hard timeout reached for namespace $ns"
      break
    fi

    sleep_safe 5
  done

  echo "✅ Namespace cleaned: $ns"

done

########################################
# INGRESS CHECK
########################################

echo ""
echo ">> Final ingress check:"
kubectl get ingress -A || true

########################################
# FINAL STATE
########################################

echo ""
echo ">> Final namespaces:"
kubectl get ns

echo ""
echo "======================================"
echo " CLEANUP COMPLETE (RECONCILED STATE)"
echo "======================================"
