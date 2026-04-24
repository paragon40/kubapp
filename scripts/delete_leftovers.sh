#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# reconciliation_engine_v2_graph.sh
# ------------------------------------------------------------
# PURPOSE:
# Graph-based AWS reconciliation engine for safe cleanup of
# Kubernetes-generated resources AFTER cluster teardown.
# ------------------------------------------------------------
# CORE SHIFT FROM v1:
# v1 = per-resource scoring
# v2 = dependency GRAPH traversal (ENI → ALB → TG → BACKENDS)
# ------------------------------------------------------------
# SAFETY MODEL:
# - Terraform-owned infra NEVER touched (NAT, VPC, Subnets, EFS FS)
# - Only K8s/Controller-generated ephemeral resources evaluated
# - Deletion decisions are GRAPH-RESOLVED, not local
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

get_eni_attachment_source() {
  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$1" \
    --query "NetworkInterfaces[0].RequesterId" \
    --output text 2>/dev/null || echo "unknown"
}

# ------------------------------------------------------------
# GRAPH RESOLUTION CORE
# ------------------------------------------------------------

resolve_eni_to_alb() {
  local eni="$1"

  # ENI description often contains LB reference
  aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].Description" \
    --output text 2>/dev/null || true
}

get_alb_from_eni() {
  local eni_desc
  eni_desc=$(resolve_eni_to_alb "$1")

  # extract LB name hint (best-effort)
  echo "$eni_desc" | grep -oE 'k8s-[a-z0-9-]+' || true
}

resolve_alb_to_tg() {
  local alb_arn="$1"

  aws elb describe-target-groups \
    --region "$REGION" \
    --load-balancer-arn "$alb_arn" \
    --query "TargetGroups[].TargetGroupArn" \
    --output text 2>/dev/null || true
}

# ------------------------------------------------------------
# DEPENDENCY VALIDATION
# ------------------------------------------------------------

validate_alb_graph() {
  local alb_arn="$1"

  local tg_count
  tg_count=$(aws elb describe-target-groups \
    --region "$REGION" \
    --load-balancer-arn "$alb_arn" \
    --query "length(TargetGroups)" \
    --output text 2>/dev/null || echo 0)

  local listener_count
  listener_count=$(aws elbv2 describe-listeners \
    --region "$REGION" \
    --load-balancer-arn "$alb_arn" \
    --query "length(Listeners)" \
    --output text 2>/dev/null || echo 0)

  # Strong deletion signal only if fully detached
  if [[ "$tg_count" -eq 0 && "$listener_count" -eq 0 ]]; then
    echo 100
  elif [[ "$tg_count" -eq 0 ]]; then
    echo 70
  else
    echo 0
  fi
}

# ------------------------------------------------------------
# ENI → GRAPH DECISION ENGINE
# ------------------------------------------------------------

process_eni() {
  local eni="$1"

  local type
  type=$(classify_eni "$eni")

  # HARD SAFETY
  if [[ "$type" == "CORE" ]]; then
    log "SKIP CORE ENI: $eni"
    return
  fi

  local source
  source=$(get_eni_attachment_source "$eni")

  log "ENI=$eni TYPE=$type SOURCE=$source"

  # --------------------------------------------------------
  # GRAPH ESCALATION: ENI → ALB
  # --------------------------------------------------------

  local alb_hint
  alb_hint=$(get_alb_from_eni "$eni")

  local alb_score=0

  if [[ -n "$alb_hint" ]]; then
    log "ENI linked to ALB candidate: $alb_hint"

    # attempt ALB ARN resolution (best effort)
    local alb_arn
    alb_arn=$(aws elb describe-load-balancers \
      --region "$REGION" \
      --query "LoadBalancers[?contains(LoadBalancerName, '$alb_hint')].LoadBalancerArn" \
      --output text 2>/dev/null || true)

    if [[ -n "$alb_arn" ]]; then
      alb_score=$(validate_alb_graph "$alb_arn")
      log "ALB GRAPH SCORE: $alb_score"
    fi
  fi

  # --------------------------------------------------------
  # FINAL DECISION LOGIC (GRAPH-AWARE)
  # --------------------------------------------------------

  local eni_score=0

  [[ "$source" == "amazon-elb" ]] && eni_score=$((eni_score+20))
  [[ "$source" == "amazon-eks" ]] && eni_score=$((eni_score+15))

  # ALB graph heavily influences ENI decision
  if (( alb_score >= 100 )); then
    eni_score=$((eni_score+60))
  elif (( alb_score >= 70 )); then
    eni_score=$((eni_score+30))
  fi

  log "FINAL ENI SCORE: $eni_score"

  if (( eni_score >= 85 )); then
    log "DELETE ENI (GRAPH CONFIRMED): $eni"
    run aws ec2 delete-network-interface \
      --region "$REGION" \
      --network-interface-id "$eni"
  else
    log "SKIP ENI (insufficient graph confidence): $eni"
  fi
}

# ------------------------------------------------------------
# MAIN ENGINE
# ------------------------------------------------------------

main() {
  log "Starting reconciliation engine v2 (GRAPH MODE)"

  assert_safety

  local enis
  enis=$(aws ec2 describe-network-interfaces \
    --region "$REGION" \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query "NetworkInterfaces[].NetworkInterfaceId" \
    --output text)

  process_load_balancers
  process_target_groups
  process_efs_mount_targets

  for eni in $enis; do
    process_eni "$eni"
  done

  log "Graph engine complete"
}

main
