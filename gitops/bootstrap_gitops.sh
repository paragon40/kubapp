#!/bin/bash
set -euo pipefail

echo "GitOps Bootstrap Starting..."

# 1. Check cluster
kubectl cluster-info >/dev/null 2>&1 || {
  echo "❌ Cluster unreachable"
  exit 1
}

# 2. Ensure ArgoCD exists
kubectl get ns argocd >/dev/null 2>&1 || {
  echo "❌ ArgoCD not installed. Install it first."
  exit 1
}

echo "✅ ArgoCD exists"

# 3. Apply root application
kubectl apply -n argocd -f gitops/infra/root-app.yml

echo "✅ Root app applied"
echo "GitOps Bootstrap Complete"
