#!/bin/bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "GitOps Bootstrap Starting..."

# Apply root application
#kubectl apply -n argocd -f "$ROOT/gitops/argocd/nginx-app.yaml"
kubectl apply -n argocd -f "$ROOT/gitops/argocd/apps/user-app.yaml"
kubectl apply -n argocd -f "$ROOT/gitops/argocd/apps/admin-app.yaml"
kubectl apply -n argocd -f "$ROOT/gitops/argocd/apps/ingress-app.yaml"

echo "✅ Root app applied"
echo "GitOps Bootstrap Complete"
