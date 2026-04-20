#!/bin/bash
set -euo pipefail

echo "GitOps Bootstrap Starting..."

# 1. Check cluster
kubectl cluster-info >/dev/null || {
  echo "❌ Cluster unreachable"
  exit 1
}

echo "✅ Cluster OK"

# 2. Check ArgoCD
kubectl get ns argocd >/dev/null || {
  echo "❌ Install ArgoCD first"
  exit 1
}

echo "✅ ArgoCD OK"

# 3. Apply root app (idempotent)
kubectl apply -n argocd -f gitops/infra/root-app.yml

echo "✅ Root app applied"

# 4. Setup SSH repo secret (safe)
kubectl get secret repo-kubapp-ssh -n argocd >/dev/null 2>&1 || \
kubectl create secret generic repo-kubapp-ssh \
  --from-file=sshPrivateKey=argocd-gitops \
  -n argocd

echo "✅ SSH secret ready"

# 5. Register repo only if missing
argocd repo list | grep kubapp >/dev/null 2>&1 || \
argocd repo add git@github.com:paragon40/kubapp.git \
  --ssh-private-key-path argocd-gitops

echo "✅ Repo registered"

# 6. Status check
kubectl get applications -n argocd || true

echo "GitOps Bootstrap Complete"
