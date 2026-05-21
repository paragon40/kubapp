#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# MODE
# ============================================================
MODE="${1:-first_run}"   # first_run | apply | destroy

# ============================================================
# CONFIG
# ============================================================
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="$PROJECT_ROOT/infra/aws"
DOMAIN="${DOMAIN:-rundailytest.site}"
KEY_NAME="tf-web-key"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/${KEY_NAME}.pem}"

REMOTE_DIR="/opt/sys_monitor"

cd "$TF_DIR"

# ============================================================
# DESTROY MODE
# ============================================================
if [[ "$MODE" == "destroy" ]]; then
  echo "🔥 DESTROY MODE"
  terraform destroy -auto-approve
  exit 0
fi

# ============================================================
# TERRAFORM INIT + APPLY
# ============================================================
terraform init -upgrade

echo "==> Terraform apply"
terraform apply -auto-approve \
  -var="key_name=${KEY_NAME}" \
  -var="ssh_cidr=$(curl -s ifconfig.me)/32"

PUBLIC_IP="$(terraform output -raw public_ip)"

echo "EC2 Public IP: $PUBLIC_IP"

ssh-keygen -R "$PUBLIC_IP" >/dev/null 2>&1 || true

# ============================================================
# WAIT FOR SSH
# ============================================================
echo "==> Waiting for SSH..."
for i in {1..40}; do
  ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" "echo ok" && break
  sleep 5
done

# ============================================================
# FIRST RUN BOOTSTRAP WAIT
# ============================================================
if [[ "$MODE" == "first_run" ]]; then
  echo "==> Waiting for cloud-init..."
  ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" << 'EOF'
set -e
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
  sleep 5
done
EOF
fi

# ============================================================
# SYNC CODE
# ============================================================
echo "==> Syncing project"
rsync -az --delete \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".git" \
  --exclude ".terraform" \
  "$PROJECT_ROOT/" \
  ubuntu@"$PUBLIC_IP":"$REMOTE_DIR/"

# ============================================================
# REMOTE DEPLOY
# ============================================================
ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" << 'EOF'
set -euo pipefail

cd /opt/sys_monitor

echo "==> Starting Docker stack"
docker compose down -v || true
docker compose up -d --build

# ============================================================
# WAIT FOR SERVICES
# ============================================================
echo "==> Waiting for services..."

for i in {1..60}; do

  GRAFANA=$(curl -fs http://localhost:3001/api/health >/dev/null && echo ok || echo no)
  PROM=$(curl -fs http://localhost:9090/-/ready >/dev/null && echo ok || echo no)
  EXPORTER=$(curl -fs http://localhost:3000/ >/dev/null && echo ok || echo no)
  SRE=$(curl -fs http://localhost:8000/ >/dev/null && echo ok || echo no)
  GITOPS=$(curl -fs http://localhost:9105/ >/dev/null && echo ok || echo no)

  echo "grafana=$GRAFANA prom=$PROM exporter=$EXPORTER sre=$SRE gitops=$GITOPS"

  if [[ "$GRAFANA" == "ok" && "$PROM" == "ok" && "$EXPORTER" == "ok" && "$SRE" == "ok" && "$GITOPS" == "ok" ]]; then
    echo "All services READY"
    break
  fi

  sleep 5
done

# ============================================================
# FINAL CHECK
# ============================================================
echo "==> Final checks"

curl -fs http://127.0.0.1:3000/ || true
curl -fs http://127.0.0.1:3001/api/health || true
curl -fs http://127.0.0.1:9090/-/ready || true
curl -fs http://127.0.0.1:8000/ || true
curl -fs http://127.0.0.1:9105/ || true
curl -fs http://127.0.0.1:9105/metrics || true

echo "========================================"
echo "Validating AWS and Kubernetes Connectivity"
echo "========================================"

# Check AWS identity
echo
echo "[1/4] Checking AWS caller identity..."
CALLER_ID=$(aws sts get-caller-identity 2>/dev/null || true)

if [[ -z "$CALLER_ID" ]]; then
  echo "ERROR: Unable to retrieve AWS caller identity."
  exit 1
fi

echo "$CALLER_ID"

# Update kubeconfig for EKS cluster
export KUBECONFIG=/home/ubuntu/.kube/config
mkdir -p $HOME/.kube
chown -R ubuntu:ubuntu $HOME/.kube

echo
echo "[2/4] Updating kubeconfig for EKS cluster 'kubapp-dev'..."
if ! aws eks update-kubeconfig \
  --region us-east-1 \
  --name kubapp-dev  \
  --kubeconfig /home/ubuntu/.kube/config; then
  echo "ERROR: Failed to update kubeconfig."
  exit 1
fi

# Verify Kubernetes API access
echo
echo "[3/4] Verifying Kubernetes API connectivity..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Unable to connect to the Kubernetes cluster."
  exit 1
fi

echo "Kubernetes API connection successful."

# Display cluster resources
echo
echo "[4/4] Listing cluster resources..."
echo
echo "Pods across all namespaces:"
kubectl get pods -A

echo
echo "Argo CD Applications:"
kubectl get applications.argoproj.io -A 2>/dev/null || \
echo "No Argo CD Application resources found."

echo "========================================"
echo "Connectivity checks completed successfully."
echo "========================================"
echo "Check gitops docker logs."
docker logs $(docker ps --filter "name=gitops-exporter" -q)
EOF

echo ""
echo "========================================"
echo "DEPLOYMENT COMPLETE"
echo "========================================"
echo ""
echo "Access your services using EC2 Public IP:"
echo ""
echo "Grafana:"
echo "  http://monitor.${DOMAIN}:3001"
echo ""
echo "Prometheus:"
echo "  http://monitor.${DOMAIN}:9090"
echo ""
echo "GitHub Exporter:"
echo "  http://app.${DOMAIN}:3000"
echo "  http://app.${DOMAIN}:3000/metrics"
echo "SRE Engine:"
echo "  http://app.${DOMAIN}:8000"
echo ""
echo "GitOps Exporter:"
echo "  http://app.${DOMAIN}:9105"
echo "  http://app.${DOMAIN}:9105/metrics"
echo ""
echo "========================================"
echo "EC2 IP: $PUBLIC_IP"
echo "========================================"
