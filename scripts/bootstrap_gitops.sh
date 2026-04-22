#!/bin/bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "GitOps Bootstrap Starting..."

# Apply root application
kubectl apply -n argocd -f "$ROOT/gitops/infra/root-app.yml"

echo "✅ Root app applied"
echo "GitOps Bootstrap Complete"
