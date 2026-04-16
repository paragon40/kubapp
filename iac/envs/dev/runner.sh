#!/usr/bin/env bash
# run.sh - KubApp Terraform Runner

set -euo pipefail

ENV=${2:-dev}
ACTION=${1:-run}

# Base directory (adjust if needed)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

INFRA_DIR="$ROOT_DIR/iac/infra"
K8S_DIR="$ROOT_DIR/iac/k8s"
ENV_DIR="$ROOT_DIR/iac/envs/$ENV"

apply_one() {
  echo "🔹 Applying $INFRA_DIR..."
  cd "$INFRA_DIR"
  terraform init
  terraform fmt -recursive
  terraform validate
  terraform plan
  terraform apply -auto-approve -var-file="terraform.tfvars"

  echo "✅ Deployment complete!"
}

case "$ACTION" in
  run)
    apply_one
    ;;
esac
