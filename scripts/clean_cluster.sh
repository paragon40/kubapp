#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
TF_CREATED_NS"${TF_CREATED_NS:-}"

echo "======================================"
echo " Kubernetes SAFE CLEANUP START"
echo "======================================"

########################################
# 0. SAFETY GUARD (NEVER RUN IN PROD)
########################################
if kubectl config current-context | grep -qi "prod"; then
  echo "❌ Refusing to run in prod context"
  exit 1
fi

########################################
# 1. DELETE ARGOCD APPLICATIONSET (ROOT OWNER)
########################################

echo ">> Checking ApplicationSets..."
APPSETS=$(kubectl get applicationsets -n argocd -o name 2>/dev/null || true)

if [[ -z "$APPSETS" ]]; then
  echo "✅ No ApplicationSets found. Nothing to clean."
  exit 0
fi

if [[ -n "$APPSETS" ]]; then
  echo ">> Deleting ApplicationSets..."
  kubectl delete $APPSETS -n argocd || true
fi

########################################
# 2. WAIT FOR APPLICATIONS TO STOP RECREATING
########################################

echo ">> Waiting for Applications to settle..."
sleep 10

echo ">> Deleting Argo Applications..."
APPS=$(kubectl get applications.argoproj.io -n argocd -o name 2>/dev/null || true)

if [[ -n "$APPS" ]]; then
  kubectl delete $APPS -n argocd || true
fi

########################################
# 3. DELETE NAMESPACED WORKLOADS (SAFE CLEAN)
########################################

NAMESPACES=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
TF_NS=$TF_CREATED_NS

for ns in $NAMESPACES; do
  if [[ "$ns" == "kube-system" || "$ns" == "default" || "$ns" == "kube-public" || "$ns" == "kube-node-lease" ]]; then
    continue
  elif [[ -n "$TF_NS" ]];
    for tf_ns in "$TF_NS"; do
      if [[ "$ns" == "$tf_ns" ]]; then
        continue
      fi
     done
  fi

  echo ">> Cleaning namespace: $ns"

  kubectl delete all --all -n "$ns" --ignore-not-found || true
  kubectl delete ingress --all -n "$ns" --ignore-not-found || true
  kubectl delete pvc --all -n "$ns" --ignore-not-found || true
done

########################################
# 4. VERIFY INGRESS IS GONE (CRITICAL FOR LB CLEANUP)
########################################

echo ">> Checking Ingress resources..."
kubectl get ingress -A || true

########################################
# 5. FORCE FINALIZER CLEANUP ONLY IF NEEDED
########################################

for ns in $NAMESPACES; do
  STATUS=$(kubectl get ns "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || true)

  if [[ "$STATUS" == "Terminating" ]]; then
    echo "⚠️ Namespace stuck: $ns - forcing finalizer removal"

    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" \
      -f <(kubectl get ns "$ns" -o json | jq '.spec.finalizers=[]') || true
  fi
done

########################################
# 6. FINAL CHECK
########################################

echo ">> Final cluster state:"
kubectl get ns
kubectl get ingress -A || true
kubectl get applicationsets -n argocd || true

echo "======================================"
echo " CLEANUP COMPLETE"
echo "======================================"
