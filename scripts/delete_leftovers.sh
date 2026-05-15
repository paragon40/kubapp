#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# PRODUCTION ENI + ELB CLEANUP ENGINE (SAFE ORPHAN DETECTION)
# ============================================================

ENV="${ENV:?ENV required}"
REGION="${AWS_REGION:?AWS_REGION required}"
VPC_ID="${VPC_ID:?VPC_ID required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
DRY_RUN="${DRY_RUN:-true}"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

awsq(){
  aws "$@" --region "$REGION" --no-cli-pager
}

run(){
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY_RUN] $*"
  else
    eval "$@"
  fi
}

[[ "$ENV" == "prod" ]] && { log "BLOCKED PROD"; exit 1; }

# ============================================================
# STEP 1: LIST ENIs
# ============================================================

log "STEP 1: LIST ENIs"
log "VPC=$VPC_ID REGION=$REGION CLUSTER=$CLUSTER_NAME"

enis=$(awsq ec2 describe-network-interfaces \
  --filters Name=vpc-id,Values="$VPC_ID" \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text)

[[ -z "$enis" ]] && { log "NO ENIs FOUND"; exit 0; }

log "ENIs FOUND:"
for eni in $enis; do
  log "FOUND ENI: $eni"
done

# ============================================================
# HELPER: ORPHAN SCORE
# ============================================================

score_eni() {
  local eni="$1"

  local json
  json=$(awsq ec2 describe-network-interfaces \
    --network-interface-ids "$eni" \
    --output json)

  local desc status requester attachment tags

  desc=$(echo "$json" | jq -r '.NetworkInterfaces[0].Description // ""')
  status=$(echo "$json" | jq -r '.NetworkInterfaces[0].Status')
  requester=$(echo "$json" | jq -r '.NetworkInterfaces[0].RequesterId // ""')
  attachment=$(echo "$json" | jq -r '.NetworkInterfaces[0].Attachment.AttachmentId // ""')
  tags=$(echo "$json" | jq -r '.NetworkInterfaces[0].TagSet // []')

  local score=0

  # ------------------------------------------------------------
  # HARD BLOCKS (immediately disqualify)
  # ------------------------------------------------------------

  if [[ "$requester" == "amazon-vpc" ]]; then
    echo "$eni|0|CORE_VPC"
    return
  fi

  if echo "$tags" | grep -q "kubernetes.io/cluster"; then
    echo "$eni|0|EKS_TAGGED"
    return
  fi

  if [[ "$desc" == *"EFS"* || "$desc" == *"efs"* ]]; then
    echo "$eni|0|EFS"
    return
  fi

  if [[ "$desc" == *"NAT Gateway"* ]]; then
    echo "$eni|0|NAT"
    return
  fi

  # ------------------------------------------------------------
  # SCORE SIGNALS
  # ------------------------------------------------------------

  [[ "$status" == "available" ]] && score=$((score + 50))

  [[ -z "$attachment" || "$attachment" == "null" ]] && score=$((score + 30))

  [[ "$desc" == *"aws-K8S-i-"* || "$desc" == *"eks"* ]] && score=$((score - 80))

  [[ "$desc" == *"ELB"* ]] && score=$((score - 50))

  echo "$eni|$score|$desc"
}

# ============================================================
# STEP 2: SCAN ENIs
# ============================================================

CANDIDATES=()

log "SCANNING ENIs..."

for eni in $enis; do

  result=$(score_eni "$eni")
  IFS='|' read -r id score reason <<< "$result"

  log "ENI=$id SCORE=$score REASON=$reason"

  if (( score >= 80 )); then
    CANDIDATES+=("$id")
  fi
done

# ============================================================
# STEP 3: FINAL CONFIRMATION CHECK
# ============================================================

if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
  log "NO SAFE ENIs TO DELETE"
  exit 0
fi

log "CANDIDATES FOR DELETION:"
printf '%s\n' "${CANDIDATES[@]}"

# ============================================================
# STEP 4: DELETE SAFELY
# ============================================================

for eni in "${CANDIDATES[@]}"; do

  log "FINAL VERIFY: $eni"

  verify=$(awsq ec2 describe-network-interfaces \
    --network-interface-ids "$eni" \
    --query "NetworkInterfaces[0].[Status,RequesterId,Attachment.AttachmentId,Description]" \
    --output text)

  log "VERIFY STATE: $verify"

  run aws ec2 delete-network-interface \
    --network-interface-id "$eni"

done

log "ENGINE COMPLETE"

