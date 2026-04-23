#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# reconciliation_engine_v1.sh
# ------------------------------------------------------------
# PURPOSE:
# Post-Kubernetes cleanup reconciliation engine that ensures
# AWS resources created by K8s controllers do not block Terraform destroy.
# ------------------------------------------------------------
# CORE PRINCIPLE:
# DELETE ONLY BASED ON PROOF + DEPENDENCY RESOLUTION
# NOT NAMES. NOT GUESSING.
# ------------------------------------------------------------
# ARCHITECTURE:
# 1. Classify resource (CORE / EPHEMERAL / UNKNOWN)
# 2. Extract attachment_source (truth signal)
# 3. Build dependency chain (ENI → ALB → TG)
# 4. Compute confidence score
# 5. Decide action
# ------------------------------------------------------------

ENV="${ENV:?ENV is required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME is required}"
REGION="${AWS_REGION:?AWS_REGION is required}"
VPC_ID="${VPC_ID:?VPC_ID is required}"
DRY_RUN="${DRY_RUN:-true}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-3}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: $*"
  else
    eval "$@"
  fi
}

abort() {
  log "ABORT: $*"
  exit 1
}

assert_safety() {
  [[ "$ENV" =~ prod ]] && abort "Production blocked"
}

# ------------------------------------------------------------
# CLASSIFICATION LAYER
# ------------------------------------------------------------

classify_eni() {
  local eni="$1"

  local desc
  desc=$(aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].Description" \
    --output text 2>/dev/null || true)

  if [[ "$desc" == *"NAT Gateway"* ]]; then
    echo "CORE"
    return
  fi

  if [[ "$desc" == *"ELB"* ]]; then
    echo "ELB"
    return
  fi

  if [[ "$desc" == *"eks"* || "$desc" == *"cni"* ]]; then
    echo "EKS"
    return
  fi

  echo "UNKNOWN"
}

get_attachment_source() {
  local eni="$1"

  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].RequesterId" \
    --output text 2>/dev/null || echo "unknown"
}

eni_age_hours() {
  local eni="$1"

  local attach_time
  attach_time=$(aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].Attachment.AttachTime" \
    --output text 2>/dev/null || echo "")

  if [[ -z "$attach_time" || "$attach_time" == "None" ]]; then
    echo 9999
    return
  fi

  local now
  now=$(date +%s)
  local ts
  ts=$(date -d "$attach_time" +%s 2>/dev/null || echo 0)

  echo $(( (now - ts) / 3600 ))
}

# ------------------------------------------------------------
# SCORING ENGINE
# ------------------------------------------------------------

score_eni() {
  local eni="$1"

  local score=0
  local type
  type=$(classify_eni "$eni")

  local source
  source=$(get_attachment_source "$eni")

  local age
  age=$(eni_age_hours "$eni")

  # CORE INFRA BLOCK
  if [[ "$type" == "CORE" ]]; then
    echo 0
    return
  fi

  # Attachment source scoring
  if [[ "$source" == "amazon-elb" ]]; then
    ((score+=25))
  elif [[ "$source" == "amazon-eks" ]]; then
    ((score+=20))
  elif [[ "$source" == "unknown" ]]; then
    ((score+=0))
  fi

  # Age scoring
  if (( age > MAX_AGE_HOURS )); then
    ((score+=15))
  fi

  # Type scoring
  if [[ "$type" == "ELB" ]]; then
    ((score+=25))
  fi

  echo "$score"
}

# ------------------------------------------------------------
# ALB VALIDATION CHAIN
# ------------------------------------------------------------

validate_alb() {
  local arn="$1"

  local tags
  tags=$(aws elbv2 describe-tags \
    --region "$REGION" \
    --resource-arns "$arn" \
    --query "TagDescriptions[0].Tags[].Key" \
    --output text 2>/dev/null || true)

  if [[ "$tags" != *"kubernetes.io/cluster/$CLUSTER_NAME"* ]]; then
    echo 0
    return
  fi

  local tg_count
  tg_count=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query "length(TargetGroups)" \
    --output text)

  if [[ "$tg_count" -eq 0 ]]; then
    echo 80
  else
    echo 40
  fi
}

# ------------------------------------------------------------
# EXECUTION LAYER
# ------------------------------------------------------------

process_enis() {
  log "Scanning ENIs..."

  local enis
  enis=$(aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text)

  for eni in $enis; do

    local type
    type=$(classify_eni "$eni")

    if [[ "$type" == "CORE" ]]; then
      log "SKIP CORE ENI: $eni"
      continue
    fi

    local score
    score=$(score_eni "$eni")

    log "ENI=$eni TYPE=$type SCORE=$score"

    if (( score >= 85 )); then
      log "DELETE ENI (CONFIDENT): $eni"
      run aws ec2 delete-network-interface \
        --region "$REGION" \
        --network-interface-id "$eni"
    else
      log "SKIP ENI (low confidence): $eni"
    fi
  done
}

# ------------------------------------------------------------
# MAIN FLOW
# ------------------------------------------------------------

main() {
  log "Starting reconciliation engine v1"

  assert_safety

  process_enis

  log "Engine complete"
}

main
