#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# v3.3 ENI + Classic ELB decision engine (strict chain)
# ============================================================
# FLOW:
# 1. list ENIs
# 2. classify attachment source
# 3. NAT/EFS/subnet => skip
# 4. ELB => validate orphan/cluster-bound
# 5. confirm + delete
# ============================================================

ENV="${ENV:?ENV required}"
REGION="${AWS_REGION:?AWS_REGION required}"
VPC_ID="${VPC_ID:?VPC_ID required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
DRY_RUN="${DRY_RUN:-true}"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

awsq(){ aws "$@" 2>/dev/null || true; }

run(){
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: $*"
  else
    eval "$@" || true
  fi
}

[[ "$ENV" == "prod" ]] && { log "BLOCKED PROD"; exit 1; }

log "STEP 1: LIST ENIs"
enis=$(awsq ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text)

for eni in $enis; do

  log "---- ENI: $eni ----"

  desc=$(awsq ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].Description" \
    --output text)

  requester=$(awsq ec2 describe-network-interfaces \
    --region "$REGION" \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].RequesterId" \
    --output text)

  log "DESC=$desc"
  log "REQUESTER=$requester"

  # --------------------------------------------------------
  # SAFE EXITS
  # --------------------------------------------------------

  LIST=("NAT Gateway" "efs" "EFS" "amazon-vpc")
  for list in "$LIST"; do
    if [[ "$desc" == *"$list"* ]]; then
      log "SKIP NAT"
      continue
    fi
  done

  # --------------------------------------------------------
  # CLASSIC ELB DETECTION
  # --------------------------------------------------------

  if [[ "$desc" == *"ELB"* ]]; then

    lb_name=$(echo "$desc" | grep -oE 'k8s-[a-zA-Z0-9-]+' || true)

    log "SUSPECT ELB LINK: $lb_name"

    if [[ -n "$lb_name" ]]; then

      state=$(awsq elb describe-load-balancers \
        --region "$REGION" \
        --load-balancer-names "$lb_name" \
        --query "LoadBalancerDescriptions[0].Instances" \
        --output text)

      if [[ "$state" == "None" || "$state" == "" ]]; then
        log "ORPHAN ELB CONFIRMED"

        log "DELETE ELB $lb_name"
        run aws elb delete-load-balancer \
          --region "$REGION" \
          --load-balancer-name "$lb_name"

        log "DELETE ENI $eni"
        run aws ec2 delete-network-interface \
          --region "$REGION" \
          --network-interface-id "$eni"

      else
        log "ELB STILL ACTIVE -> SKIP"
      fi
    fi

    continue
  fi

  # --------------------------------------------------------
  # DEFAULT SAFE SKIP
  # --------------------------------------------------------

  log "NO RULE MATCH -> SKIP $eni"

done

log "DONE ENGINE v3.3"
