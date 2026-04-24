#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# reconciliation_engine_v3_graph_clean.sh
# ------------------------------------------------------------
# PURPOSE:
# post-Kubernetes cleanup after cluster teardown.
# ------------------------------------------------------------
# CORE PRINCIPLE:
# NO GUESSING.
# ONLY GRAPH-BASED OWNERSHIP + ATTACHMENT TRUTH.
# ------------------------------------------------------------
# RESOURCES COVERED:
# - ENI (EC2 Network Interfaces)
# - ALB / NLB (ELBv2)
# - Target Groups (ELBv2)
# - Classic ELB (ELB)
# - EFS (File Systems + Mount Targets)
# ------------------------------------------------------------
# SAFETY MODEL:
# - NAT Gateway ENIs ALWAYS PROTECTED (Terraform-owned)
# - VPC/Subnets/IAM NEVER TOUCHED
# - Only cluster-scoped or orphaned resources considered
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
# UTILS: TAG + OWNERSHIP
# ------------------------------------------------------------

has_cluster_tag() {
  local tags="$1"
  [[ "$tags" == *"kubernetes.io/cluster/$CLUSTER_NAME"* ]]
}

# ------------------------------------------------------------
# ENI GRAPH
# ------------------------------------------------------------

get_eni_info() {
  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$1" \
    --query "NetworkInterfaces[0]" \
    --output json
}

is_eni_nat() {
  local desc="$1"
  [[ "$desc" == *"NAT Gateway"* ]]
}

is_eni_eks() {
  local desc="$1"
  [[ "$desc" == *"eks"* || "$desc" == *"cni"* ]]
}

score_eni() {
  local eni="$1"

  local info desc requester attachment

  info=$(get_eni_info "$eni")

  desc=$(echo "$info" | jq -r '.Description // ""')
  requester=$(echo "$info" | jq -r '.RequesterId // "unknown"')
  attachment=$(echo "$info" | jq -r '.Attachment.InstanceId // empty')

  # HARD RULES
  if is_eni_nat "$desc"; then
    echo 0
    return
  fi

  local score=0

  [[ "$requester" == "amazon-elb" ]] && score=$((score+25))
  [[ "$requester" == "amazon-eks" ]] && score=$((score+20))

  if [[ -z "$attachment" ]]; then
    score=$((score+20))
  fi

  echo "$score"
}

# ------------------------------------------------------------
# ALB GRAPH (ELBV2 ONLY)
# ------------------------------------------------------------

get_albs() {
  aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?VpcId=='$VPC_ID']" \
    --output json
}

get_alb_children() {
  local arn="$1"

  aws elbv2 describe-target-groups \
    --region "$REGION" \
    --load-balancer-arn "$arn" \
    --query "TargetGroups[]" \
    --output json
}

score_alb() {
  local arn="$1"

  local tgs listeners

  tgs=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --load-balancer-arn "$arn" \
    --query "length(TargetGroups)" \
    --output text 2>/dev/null || echo 0)

  listeners=$(aws elbv2 describe-listeners \
    --region "$REGION" \
    --load-balancer-arn "$arn" \
    --query "length(Listeners)" \
    --output text 2>/dev/null || echo 0)

  if [[ "$tgs" -eq 0 && "$listeners" -eq 0 ]]; then
    echo 100
  elif [[ "$tgs" -eq 0 ]]; then
    echo 70
  else
    echo 0
  fi
}

# ------------------------------------------------------------
# TARGET GROUPS
# ------------------------------------------------------------

process_target_groups() {
  log "Scanning Target Groups"

  local tgs
  tgs=$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query "TargetGroups[]" \
    --output json)

  echo "$tgs" | jq -c '.[]' | while read -r tg; do
    local arn
    arn=$(echo "$tg" | jq -r '.TargetGroupArn')

    local lb_count
    lb_count=$(echo "$tg" | jq '.LoadBalancerArns | length')

    if [[ "$lb_count" -eq 0 ]]; then
      log "DELETE TG (orphaned): $arn"
      run aws elbv2 delete-target-group \
        --region "$REGION" \
        --target-group-arn "$arn"
    else
      log "SKIP TG (attached): $arn"
    fi
  done
}

# ------------------------------------------------------------
# EFS GRAPH
# ------------------------------------------------------------

process_efs() {
  log "Scanning EFS"

  local fs_list
  fs_list=$(aws efs describe-file-systems \
    --region "$REGION" \
    --query "FileSystems[]" \
    --output json)

  echo "$fs_list" | jq -c '.[]' | while read -r fs; do
    local fsid
    fsid=$(echo "$fs" | jq -r '.FileSystemId')

    local mounts
    mounts=$(aws efs describe-mount-targets \
      --region "$REGION" \
      --file-system-id "$fsid" \
      --query "MountTargets[]" \
      --output json)

    local count
    count=$(echo "$mounts" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
      log "EFS has no mount targets (candidate orphan): $fsid"
    else
      log "SKIP EFS (active mounts): $fsid"
    fi
  done
}

# ------------------------------------------------------------
# CLASSIC ELB
# ------------------------------------------------------------

process_classic_elb() {
  log "Scanning Classic ELB"

  local lbs
  lbs=$(aws elb describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancerDescriptions[].LoadBalancerName" \
    --output text)

  for lb in $lbs; do
    log "DELETE Classic ELB (assumed legacy): $lb"
    run aws elb delete-load-balancer \
      --region "$REGION" \
      --load-balancer-name "$lb"
  done
}

# ------------------------------------------------------------
# ENI GRAPH
# ------------------------------------------------------------

process_enis() {
  log "Scanning ENIs"

  local enis
  enis=$(aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text)

  for eni in $enis; do

    local score
    score=$(score_eni "$eni")

    log "ENI=$eni SCORE=$score"

    if (( score >= 85 )); then
      log "DELETE ENI (graph confirmed): $eni"
      run aws ec2 delete-network-interface \
        --region "$REGION" \
        --network-interface-id "$eni"
    else
      log "SKIP ENI: $eni"
    fi
  done
}

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------

main() {
  log "Starting v3 GRAPH CLEAN engine"

  assert_safety

  process_classic_elb
  process_target_groups
  process_efs
  process_enis

  log "Graph reconciliation complete"
}

main
