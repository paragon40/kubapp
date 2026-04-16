#!/bin/bash

set -e

echo "🚀 Starting Kubapp GitOps Bootstrap..."
kubectl apply -f gitops/infra/root-app.yml

# ==============================
# 1. Check kubectl access
# ==============================
echo "🔍 Checking cluster access..."

kubectl cluster-info >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "❌ kubectl cannot reach cluster. Exiting."
  exit 1
fi

echo "✅ Cluster access OK"


# ==============================
# 2. Check ArgoCD namespace
# ==============================
echo "🔍 Checking ArgoCD namespace..."

kubectl get ns argocd >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "❌ ArgoCD namespace not found. Install ArgoCD first."
  exit 1
fi

echo "✅ ArgoCD namespace exists"


# ==============================
# 3. Apply root-app (GitOps bootstrap)
# ==============================
echo "🚀 Applying ArgoCD root application..."

kubectl apply -n argocd -f gitops/infra/root-app.yml

echo "✅ Root app applied"


# ==============================
# 4. Wait for ArgoCD Applications
# ==============================
echo "⏳ Waiting for ArgoCD Applications to appear..."

sleep 10

kubectl get applications -n argocd


# ==============================
# 5. Quick cluster sanity check
# ==============================
echo "🔍 Checking cluster resources..."

kubectl get pods -A | head -20
kubectl get ingress -A || true

echo "🎉 GitOps bootstrap completed successfully!"
echo "👉 Now ArgoCD is in control. Use Git commits for deployments."

# create k8s secret
kubectl create secret docker-registry dockerhub-secret \
  --docker-username=Username \
  --docker-password=YOUR_PASSWORD \
  --docker-email=you@example.com \
  -n admin

