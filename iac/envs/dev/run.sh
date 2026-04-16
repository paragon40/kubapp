#!/usr/bin/env bash
# run.sh - KubApp Terraform Runner

set -euo pipefail

ENV=${2:-dev}
ACTION=${1:-apply}

# Base directory (adjust if needed)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"

INFRA_DIR="$ROOT_DIR/iac/infra"
K8S_DIR="$ROOT_DIR/iac/k8s"
ENV_DIR="$ROOT_DIR/iac/envs/$ENV"

run_apply() {
  echo "Deploying KubApp (ENV: $ENV)"

  echo "🔹 Applying INFRA..."
  cd "$INFRA_DIR"
  terraform init
  terraform fmt -recursive
  terraform validate
  terraform plan -var-file="terraform.tfvars"
  echo "Applying..."
  terraform apply -auto-approve -var-file="terraform.tfvars"

  echo "🔹 Applying K8S..."
  cd "$K8S_DIR"
  terraform init
  terraform fmt -recursive
  terraform validate
  terraform plan -var-file="terraform.tfvars"
  echo "Applying..."
  terraform apply -auto-approve -var-file="terraform.tfvars"

  echo "✅ Deployment complete!"
}

run_destroy() {
  echo "⚠️ Destroying KubApp (ENV: $ENV)"

  echo "💣 Destroying K8S..."
  cd "$K8S_DIR"
  terraform init
  terraform destroy -auto-approve -var-file="terraform.tfvars"

  echo "💣 Destroying INFRA..."
  cd "$INFRA_DIR"
  terraform init
  terraform destroy -auto-approve -var-file="terraform.tfvars"

  echo "Deleting logs....."
  ./cleanup_logs.sh

  echo "💥 Destroy complete!"
}

case "$ACTION" in
  apply)
    run_apply
    ;;
  destroy)
    run_destroy
    ;;
  *)
    echo "Usage: ./run.sh [apply|destroy] [env]"
    echo "Example: ./run.sh apply dev"
    exit 1
    ;;
esac
