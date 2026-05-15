#!/bin/bash
set -euxo pipefail

apt-get update
apt-get install -y docker.io docker-compose-v2 git
systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu

mkdir -p /opt/sys_monitor
chown -R ubuntu:ubuntu /opt/sys_monitor


