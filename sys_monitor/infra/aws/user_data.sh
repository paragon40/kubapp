#!/bin/bash
set -euxo pipefail

apt-get update -y

apt-get install -y \
  docker.io \
  docker-compose-v2 \
  git \
  dnsutils \
  curl \
  unzip

# AWS CLI v2
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# kubectl
K8S_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
curl -fsSL "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# Docker
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Project directory
mkdir -p /opt/sys_monitor
chown -R ubuntu:ubuntu /opt/sys_monitor

aws --version
kubectl version --client
docker --version

