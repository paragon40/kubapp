#!/bin/bash
set -euo pipefail


ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "GitOps Bootstrap Starting..."

# Apply root application
kubectl apply  -n argocd -f "$ROOT/gitops/argocd/appset.yaml"
kubectl apply  -n argocd -f "$ROOT/gitops/argocd/ingress.yaml"
echo "Applying backend proxies..."
kubectl apply -f "$ROOT/gitops/envs/dev/backend_proxy/grafana-proxy.yaml"
kubectl apply -f "$ROOT/gitops/envs/dev/backend_proxy/prometheus-proxy.yaml"
kubectl apply -f "$ROOT/gitops/envs/dev/backend_proxy/alertmanager-proxy.yaml"
kubectl apply -f "$ROOT/gitops/envs/dev/backend_proxy/argocd-proxy.yaml"

echo "✅ Root app applied"
echo "GitOps Bootstrap Complete"
