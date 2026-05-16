#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# SYS_MONITOR AWS DEPLOYMENT SCRIPT
# ============================================================
# This script:
#   1. Initializes Terraform
#   2. Provisions AWS infrastructure
#   3. Retrieves EC2 public IP
#   4. Waits for SSH availability
#   5. Copies the sys_monitor project to EC2
#   6. Starts Docker Compose remotely
#   7. Prints access URLs
#
# Required environment variables:
#   export KEY_NAME=my-aws-keypair
#
# Optional:
#   export AWS_REGION=us-east-1
# ============================================================

PROJECT_ROOT="$HOME/Main/devops/kubapp/sys_monitor"
TF_DIR="$PROJECT_ROOT/infra/aws"
REMOTE_USER="ubuntu"
REMOTE_DIR="/opt/sys_monitor"
export KEY_NAME=tf-web-key
SSH_KEY="${SSH_KEY:-$HOME/.ssh/${KEY_NAME}.pem}"

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------
if [[ -z "${KEY_NAME:-}" ]]; then
  echo "ERROR: KEY_NAME environment variable is not set."
  exit 1
fi

if [[ ! -f "$SSH_KEY" ]]; then
  echo "ERROR: SSH key not found: $SSH_KEY"
  echo "Set a custom key path if needed:"
  echo "  export SSH_KEY=/path/to/key.pem"
  exit 1
fi

cd "$TF_DIR"

# ------------------------------------------------------------
# Terraform Init
# ------------------------------------------------------------
echo "============================================================"
echo "Terraform Init"
echo "============================================================"
terraform init

# ------------------------------------------------------------
# Terraform Apply
# ------------------------------------------------------------
MY_IP="$(curl -s ifconfig.me)/32"

echo "============================================================"
echo "Terraform Apply"
echo "============================================================"
terraform apply -auto-approve \
  -var="key_name=${KEY_NAME}" \
  -var="ssh_cidr=${MY_IP}"

# ------------------------------------------------------------
# Retrieve Public IP
# ------------------------------------------------------------
PUBLIC_IP="$(terraform output -raw public_ip)"

if [[ -z "$PUBLIC_IP" ]]; then
  echo "ERROR: Public IP not found."
  exit 1
fi

echo "============================================================"
echo "EC2 Public IP: $PUBLIC_IP"
echo "============================================================"

# ------------------------------------------------------------
# Wait for SSH
# ------------------------------------------------------------
echo "Waiting for SSH to become available..."

for i in {1..30}; do
  if ssh -o StrictHostKeyChecking=no \
         -o ConnectTimeout=5 \
         -i "$SSH_KEY" \
         "${REMOTE_USER}@${PUBLIC_IP}" \
         "echo SSH is ready" >/dev/null 2>&1; then
    echo "SSH is ready."
    break
  fi

  if [[ "$i" -eq 30 ]]; then
    echo "ERROR: SSH did not become available."
    exit 1
  fi

  sleep 10
done

# ------------------------------------------------------------
# Copy Project
# ------------------------------------------------------------
echo "============================================================"
echo "Copying project to EC2"
echo "============================================================"

rsync -avz --delete \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".git" \
  --exclude ".venv" \
  --exclude "__pycache__" \
  --exclude ".terraform" \
  --exclude "*.tfstate*" \
  "$PROJECT_ROOT/" \
  "${REMOTE_USER}@${PUBLIC_IP}:${REMOTE_DIR}/"

# ------------------------------------------------------------
# Start Docker Compose
# ------------------------------------------------------------
echo "============================================================"
echo "Starting Docker Compose on EC2"
echo "============================================================"

ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    "${REMOTE_USER}@${PUBLIC_IP}" << EOF
set -euo pipefail

cd ${REMOTE_DIR}

sudo docker compose down || true
sudo docker compose up -d --build

echo
echo "Running containers:"
sudo docker ps
EOF

# ------------------------------------------------------------
# Health Checks
# ------------------------------------------------------------
echo "============================================================"
echo "Waiting for services"
echo "============================================================"

sleep 20

for url in \
  "http://${PUBLIC_IP}:3000/" \
  "http://${PUBLIC_IP}:3000/metrics" \
  "http://${PUBLIC_IP}:3001/login" \
  "http://${PUBLIC_IP}:9090/-/healthy"
do
  echo
  echo "Checking: $url"
  curl -fsS "$url" >/dev/null && echo "OK" || echo "FAILED"
done

# ------------------------------------------------------------
# Final Output
# ------------------------------------------------------------
echo "Generating test data..."
export IP=$PUBLIC_IP
bash ./generate.sh

echo
echo "============================================================"
echo "DEPLOYMENT COMPLETE"
echo "============================================================"
echo "EC2 Public IP:      $PUBLIC_IP"
echo "Webhook Endpoint:   http://${PUBLIC_IP}:3000/webhook/github"
echo "Grafana:            http://${PUBLIC_IP}:3001"
echo "Prometheus:         http://${PUBLIC_IP}:9090"
echo "SSH:"
echo "  ssh -i $SSH_KEY ${REMOTE_USER}@${PUBLIC_IP}"
echo "============================================================"

