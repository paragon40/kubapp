#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# delete_leftovers.sh
#
# Focus:
# Only cleanup AWS resources commonly created dynamically by
# EKS / Kubernetes and NOT directly tracked by Terraform.
#
# Included:
# - Classic ELB / ALB / NLB
# - ENIs created by ELB / EKS
# - EFS Mount Targets (and related orphaned EFS checks)
#
# Excluded:
# - VPC
# - Subnets
# - Route tables
# - IAM
# - Security Groups managed directly by Terraform
#
# Goal:
# Prevent terraform destroy failures caused by hidden AWS
# dependencies that Kubernetes created outside Terraform.
# ------------------------------------------------------------

ENV="${ENV:?ENV is required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME is required}"
REGION="${AWS_REGION:?AWS_REGION is required}"
PROJECT="${PROJECT:-}"
VPC_ID="${VPC_ID:-}"

PROTECTED_PATTERNS=(
  "prod"
  "production"
  "live"
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

is_protected() {
  local value="${1,,}"

  for p in "${PROTECTED_PATTERNS[@]}"; do
    if [[ "$value" == *"$p"* ]]; then
      return 0
    fi
  done

  return 1
}

matches_scope() {
  local value="${1,,}"

  [[ "$value" == *"${CLUSTER_NAME,,}"* ]] && return 0
  [[ -n "$PROJECT" && "$value" == *"${PROJECT,,}"* ]] && return 0
  [[ "$value" == *"${ENV,,}"* ]] && return 0
  [[ "$value" == *"k8s"* ]] && return 0
  [[ "$value" == *"ingress"* ]] && return 0
  [[ "$value" == *"elb"* ]] && return 0
  [[ "$value" == *"eks"* ]] && return 0
  [[ "$value" == *"argocd"* ]] && return 0

  return 1
}

safe_delete() {
  local name="$1"

  if is_protected "$name"; then
    log "SKIP protected resource: $name"
    return 1
  fi

  if matches_scope "$name"; then
    return 0
  fi

  log "SKIP unmatched resource: $name"
  return 1
}

log "================================================="
log "Cleaning dynamic EKS leftovers"
log "ENV          = $ENV"
log "CLUSTER      = $CLUSTER_NAME"
log "PROJECT      = ${PROJECT:-unset}"
log "REGION       = $REGION"
log "VPC ID       = ${VPC_ID:-unset}"
log "================================================="

if [[ "$ENV" == "prod" || "$ENV" == "production" ]]; then
  echo "❌ PRODUCTION DETECTED - ABORTING"
  exit 1
fi

############################################################
# 1. CLASSIC ELB (Service type LoadBalancer)
############################################################

log "Checking Classic ELBs..."

CLASSIC_LBS=$(aws elb describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancerDescriptions[].LoadBalancerName" \
  --output text || true)

if [[ -n "${CLASSIC_LBS// }" ]]; then
  for lb in $CLASSIC_LBS; do
    if safe_delete "$lb"; then
      log "Deleting Classic ELB: $lb"
      aws elb delete-load-balancer \
        --region "$REGION" \
        --load-balancer-name "$lb" || true
    fi
  done
  log "Waiting for AWS to release ENIs from deleted LBs..."
  sleep 20
else
  log "No Classic ELBs found"
fi

############################################################
# 2. ALB / NLB (Ingress / Controller managed)
############################################################

log "Checking ALB / NLB..."

ELBV2_LBS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[].LoadBalancerArn" \
  --output text || true)

if [[ -n "${ELBV2_LBS// }" ]]; then
  for arn in $ELBV2_LBS; do
    name=$(basename "$arn")

    if safe_delete "$name"; then
      log "Deleting ELBv2: $name"
      aws elbv2 delete-load-balancer \
        --region "$REGION" \
        --load-balancer-arn "$arn" || true
    fi
  done
  log "Waiting for AWS to release ENIs from deleted LBs..."
  sleep 20
else
  log "No ALB/NLB found"
fi

############################################################
# 3. TARGET GROUPS (often left behind after ALB)
############################################################

log "Checking Target Groups..."

TARGET_GROUPS=$(aws elbv2 describe-target-groups \
  --region "$REGION" \
  --query "TargetGroups[].TargetGroupArn" \
  --output text || true)

if [[ -n "${TARGET_GROUPS// }" ]]; then
  for tg in $TARGET_GROUPS; do
    name=$(basename "$tg")

    if safe_delete "$name"; then
      log "Deleting Target Group: $name"
      aws elbv2 delete-target-group \
        --region "$REGION" \
        --target-group-arn "$tg" || true
    fi
  done
else
  log "No Target Groups found"
fi

############################################################
# 4. ENIs (LB-created + EKS-created leftovers)
############################################################

log "Checking ENIs..."

if [[ -n "$VPC_ID" ]]; then
  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "NetworkInterfaces[*].[NetworkInterfaceId,Description,Status,RequesterId]" \
    --output table || true
fi

AVAILABLE_ENIS=$(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters "Name=status,Values=available" \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text || true)

if [[ -n "${AVAILABLE_ENIS// }" ]]; then
  for eni in $AVAILABLE_ENIS; do
    desc=$(aws ec2 describe-network-interfaces \
      --region "$REGION" \
      --network-interface-ids "$eni" \
      --query "NetworkInterfaces[0].Description" \
      --output text 2>/dev/null || true)

    if safe_delete "$desc"; then
      log "Deleting orphaned ENI: $eni ($desc)"
      aws ec2 delete-network-interface \
        --region "$REGION" \
        --network-interface-id "$eni" || true
    fi
  done
else
  log "No deletable ENIs found"
fi

############################################################
# 5. EFS + MOUNT TARGETS
############################################################

log "Checking EFS Mount Targets..."

FILESYSTEMS=$(aws efs describe-file-systems \
  --region "$REGION" \
  --query "FileSystems[].FileSystemId" \
  --output text || true)

if [[ -n "${FILESYSTEMS// }" ]]; then
  for fs in $FILESYSTEMS; do
    if safe_delete "$fs"; then
      MOUNTS=$(aws efs describe-mount-targets \
        --region "$REGION" \
        --file-system-id "$fs" \
        --query "MountTargets[].MountTargetId" \
        --output text || true)

      for mt in $MOUNTS; do
        log "Deleting EFS Mount Target: $mt"
        aws efs delete-mount-target \
          --region "$REGION" \
          --mount-target-id "$mt" || true
      done
    fi
  done
else
  log "No EFS resources found"
fi

log "================================================="
log "Eks Resource Leftover cleanup completed"
log "================================================="
