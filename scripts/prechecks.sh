#!/bin/bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "Running Prechecks..."

kubectl cluster-info >/dev/null || {
  echo "❌ Cluster unreachable"
  exit 1
}

kubectl get ns argocd >/dev/null || {
  echo "❌ ArgoCD not installed"
  exit 1
}

test -f "$ROOT/gitops/infra/root-app.yml" || {
  echo "❌ root-app.yml missing"
  exit 1
}

echo "✅ Prechecks passed"
