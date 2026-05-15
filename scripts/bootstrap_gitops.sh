#!/bin/bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "---- PREVIEW ----"
kubectl apply -f "$FILE" --dry-run=client -o yaml

echo "GitOps Bootstrap Starting..."

# Apply root application
kubectl apply  -n argocd -f "$ROOT/gitops/argocd/appset.yaml" -v=8
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
kubectl apply  -n argocd -f "$ROOT/gitops/argocd/ingress.yaml" -v=8

echo "✅ Root app applied"
echo "GitOps Bootstrap Complete"
