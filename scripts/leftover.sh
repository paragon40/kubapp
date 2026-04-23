#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# delete_leftovers.sh
#
# Purpose:
# Safely detect and delete orphaned AWS resources that commonly
# block terraform destroy for EKS / Kubernetes environments.
#
# Strategy:
# - Only operate on NON-PROD resources
# - Skip anything matching protected patterns like *prod*
# - Filter by:
#     - cluster name
#     - project name
#     - environment name
#     - VPC ID (when available)
#     - Kubernetes k8s-* / ingress patterns
# - Delete in dependency-safe order
#
# Requires:
# - aws cli
# - jq
# - terraform outputs available
# ------------------------------------------------------------

AWS_REGION="${AWS_REGION:-us-east-1}"
ENV="${ENV:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
PROJECT="${PROJECT:-}"
VPC_ID="${VPC_ID:-}"

# Protected patterns (never touch)
PROTECTED_PATTERNS=(
  "prod"
  "production"
  "live"
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

warn() {
  echo "[WARN] $*"
}

fail() {
  echo "[ERROR] $*"
  exit 1
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

contains_protected_pattern() {
  local value="${1,,}"

  for p in "${PROTECTED_PATTERNS[@]}"; do
    if [[ "$value" == *"$p"* ]]; then
      return 0
    fi
  done

  return 1
}

safe_match() {
  local value="${1,,}"

  [[ -n "$CLUSTER_NAME" && "$value" == *"${CLUSTER_NAME,,}"* ]] && return 0
  [[ -n "$PROJECT" && "$value" == *"${PROJECT,,}"* ]] && return 0
  [[ -n "$ENV" && "$value" == *"${ENV,,}"* ]] && return 0
  [[ "$value" == *"k8s"* ]] && return 0
  [[ "$value" == *"ingress"* ]] && return 0
  [[ "$value" == *"argocd"* ]] && return 0

  return 1
}

safe_delete_guard() {
  local resource="$1"

  if contains_protected_pattern "$resource"; then
    warn "Skipping protected resource: $resource"
    return 1
  fi

  if safe_match "$resource"; then
    return 0
  fi

  warn "Skipping unmatched resource: $resource"
  return 1
}

require_bin aws
require_bin jq

log "Starting leftover cleanup"
log "Region      : $AWS_REGION"
log "Environment : ${ENV:-unset}"
log "Cluster     : ${CLUSTER_NAME:-unset}"
log "Project     : ${PROJECT:-unset}"
log "VPC ID      : ${VPC_ID:-unset}"

# ------------------------------------------------------------
# CLASSIC ELB
# ------------------------------------------------------------
cleanup_classic_elb() {
  log "Checking Classic ELBs..."

  mapfile -t lbs < <(
    aws elb describe-load-balancers \
      --region "$AWS_REGION" \
      --query 'LoadBalancerDescriptions[].LoadBalancerName' \
      --output text | tr '\t' '\n' || true
  )

  for lb in "${lbs[@]}"; do
    [[ -z "$lb" ]] && continue

    if safe_delete_guard "$lb"; then
      log "Deleting Classic ELB: $lb"
      aws elb delete-load-balancer \
        --region "$AWS_REGION" \
        --load-balancer-name "$lb" || true
    fi
  done
}

# ------------------------------------------------------------
# ALB / NLB
# ------------------------------------------------------------
cleanup_elbv2() {
  log "Checking ALB/NLB..."

  mapfile -t arns < <(
    aws elbv2 describe-load-balancers \
      --region "$AWS_REGION" \
      --query 'LoadBalancers[].LoadBalancerArn' \
      --output text | tr '\t' '\n' || true
  )

  for arn in "${arns[@]}"; do
    [[ -z "$arn" ]] && continue

    name=$(basename "$arn")

    if safe_delete_guard "$name"; then
      log "Deleting ELBv2: $name"
      aws elbv2 delete-load-balancer \
        --region "$AWS_REGION" \
        --load-balancer-arn "$arn" || true
    fi
  done
}

# ------------------------------------------------------------
# TARGET GROUPS
# ------------------------------------------------------------
cleanup_target_groups() {
  log "Checking Target Groups..."

  mapfile -t tgs < <(
    aws elbv2 describe-target-groups \
      --region "$AWS_REGION" \
      --query 'TargetGroups[].TargetGroupArn' \
      --output text | tr '\t' '\n' || true
  )

  for tg in "${tgs[@]}"; do
    [[ -z "$tg" ]] && continue

    name=$(basename "$tg")

    if safe_delete_guard "$name"; then
      log "Deleting Target Group: $name"
      aws elbv2 delete-target-group \
        --region "$AWS_REGION" \
        --target-group-arn "$tg" || true
    fi
  done
}

# ------------------------------------------------------------
# ENIs (visibility only - usually auto-removed by LB deletion)
# ------------------------------------------------------------
cleanup_enis() {
  log "Checking ENIs..."

  if [[ -z "$VPC_ID" ]]; then
    warn "VPC_ID not provided, skipping ENI scoped cleanup"
    return
  fi

  aws ec2 describe-network-interfaces \
    --region "$AWS_REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query 'NetworkInterfaces[*].[NetworkInterfaceId,Description,Status,RequesterId]' \
    --output table || true

  log "ENIs are usually requester-managed. Delete ELBs first and AWS will clean them."
}

# ------------------------------------------------------------
# SECURITY GROUPS
# ------------------------------------------------------------
cleanup_security_groups() {
  log "Checking Security Groups..."

  if [[ -z "$VPC_ID" ]]; then
    warn "VPC_ID not provided, skipping SG cleanup"
    return
  fi

  mapfile -t sgs < <(
    aws ec2 describe-security-groups \
      --region "$AWS_REGION" \
      --filters Name=vpc-id,Values="$VPC_ID" \
      --query 'SecurityGroups[].GroupId' \
      --output text | tr '\t' '\n' || true
  )

  for sg in "${sgs[@]}"; do
    [[ -z "$sg" ]] && continue

    name=$(aws ec2 describe-security-groups \
      --region "$AWS_REGION" \
      --group-ids "$sg" \
      --query 'SecurityGroups[0].GroupName' \
      --output text 2>/dev/null || true)

    if safe_delete_guard "$name"; then
      log "Deleting Security Group: $name ($sg)"
      aws ec2 delete-security-group \
        --region "$AWS_REGION" \
        --group-id "$sg" || true
    fi
  done
}

# ------------------------------------------------------------
# EFS MOUNT TARGETS
# ------------------------------------------------------------
cleanup_efs_mount_targets() {
  log "Checking EFS mount targets..."

  mapfile -t filesystems < <(
    aws efs describe-file-systems \
      --region "$AWS_REGION" \
      --query 'FileSystems[].FileSystemId' \
      --output text | tr '\t' '\n' || true
  )

  for fs in "${filesystems[@]}"; do
    [[ -z "$fs" ]] && continue

    if safe_delete_guard "$fs"; then
      mapfile -t mts < <(
        aws efs describe-mount-targets \
          --region "$AWS_REGION" \
          --file-system-id "$fs" \
          --query 'MountTargets[].MountTargetId' \
          --output text | tr '\t' '\n' || true
      )

      for mt in "${mts[@]}"; do
        [[ -z "$mt" ]] && continue
        log "Deleting EFS mount target: $mt"
        aws efs delete-mount-target \
          --region "$AWS_REGION" \
          --mount-target-id "$mt" || true
      done
    fi
  done
}

# ------------------------------------------------------------
# EXECUTION ORDER
# ------------------------------------------------------------
cleanup_classic_elb
cleanup_elbv2

log "Waiting for ELB cleanup propagation..."
sleep 30

cleanup_target_groups
cleanup_enis
cleanup_security_groups
cleanup_efs_mount_targets

log "Leftover cleanup completed"
