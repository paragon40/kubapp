#!/bin/bash
set -euxo pipefail

# ============================================================
# SYSTEM SETUP
# ============================================================
apt-get update -y

apt-get install -y \
  docker.io \
  docker-compose-plugin \
  git \
  dnsutils \
  curl \
  unzip \
  jq

# ============================================================
# AWS CLI v2
# ============================================================
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

K8S_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

mkdir -p /opt/sys_monitor
chown -R ubuntu:ubuntu /opt/sys_monitor

echo "Checking AWS identity..."
aws sts get-caller-identity || true

echo "AWS CLI version:"
aws --version

echo "kubectl version:"
kubectl version --client

echo "docker version:"
docker --version

echo "export AWS_REGION=us-east-1" >> /home/ubuntu/.bashrc
echo "export AWS_DEFAULT_REGION=us-east-1" >> /home/ubuntu/.bashrc
chown ubuntu:ubuntu /home/ubuntu/.bashrc
