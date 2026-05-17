#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$HOME/Main/devops/kubapp/sys_monitor"
TF_DIR="$PROJECT_ROOT/infra/aws"
REMOTE_USER="ubuntu"
REMOTE_DIR="/opt/sys_monitor"

EMAIL="rundailytest@gmail.com"
DOMAIN="sys-monitor.rundailytest.site"

export KEY_NAME=tf-web-key
SSH_KEY="${SSH_KEY:-$HOME/.ssh/${KEY_NAME}.pem}"
REPO="${REPO:-paragon40/kubapp}"

cd "$TF_DIR"

# ----------------------------
# TERRAFORM
# ----------------------------
terraform init

MY_IP="$(curl -s ifconfig.me)/32"

terraform apply -auto-approve \
  -var="key_name=${KEY_NAME}" \
  -var="ssh_cidr=${MY_IP}"

PUBLIC_IP="$(terraform output -raw public_ip)"

echo "EC2: $PUBLIC_IP"

WEBHOOK_URL="$(terraform output -raw github_webhook_url)"

# ----------------------------
# GITHUB SECRET
# ----------------------------
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh secret set SYS_MONITOR_WEBHOOK \
    --repo "$REPO" \
    --body "$WEBHOOK_URL"
fi

# ----------------------------
# SSH WAIT
# ----------------------------
for i in {1..30}; do
  if ssh -o StrictHostKeyChecking=no \
         -o ConnectTimeout=5 \
         -i "$SSH_KEY" \
         ubuntu@"$PUBLIC_IP" "echo ok"; then
    break
  fi
  sleep 10
done

# ----------------------------
# SYNC
# ----------------------------
rsync -avz --delete --no-perms --no-owner --no-group \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  --exclude ".git" \
  --exclude ".terraform" \
  "$PROJECT_ROOT/" \
  ubuntu@"$PUBLIC_IP":"$REMOTE_DIR/"

# ----------------------------
# REMOTE SETUP
# ----------------------------
ssh -i "$SSH_KEY" ubuntu@"$PUBLIC_IP" << EOF

set -euo pipefail

mkdir -p /opt/sys_monitor
chown -R ubuntu:ubuntu /opt/sys_monitor

cd /opt/sys_monitor

# ----------------------------
# NGINX CONFIG
# ----------------------------
sudo cp infra/aws/nginx.conf /etc/nginx/sites-available/sys-monitor
sudo ln -sf /etc/nginx/sites-available/sys-monitor /etc/nginx/sites-enabled/sys-monitor

sudo nginx -t
sudo systemctl restart nginx

# ----------------------------
# WAIT FOR DNS
# ----------------------------
echo "Waiting for DNS..."
for i in {1..30}; do
  if dig +short $DOMAIN | grep -q .; then
    echo "DNS ready"
    break
  fi
  sleep 5
done

# ----------------------------
# WAIT FOR HTTP
# ----------------------------
echo "Waiting for HTTP..."
for i in {1..30}; do
  if curl -sI http://$DOMAIN >/dev/null; then
    echo "HTTP ready"
    break
  fi
  sleep 5
done

# ----------------------------
# CERTBOT
# ----------------------------
sudo certbot --nginx \
  -d $DOMAIN \
  -m $EMAIL \
  --agree-tos \
  --non-interactive \
  --redirect || true

echo "Nginx + HTTPS ready"

EOF

echo "DONE → https://sys-monitor.rundailytest.site"
