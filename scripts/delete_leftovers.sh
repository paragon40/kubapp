#!/usr/bin/env bash
set -euo pipefail

ENV="${ENV:?ENV is required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME is required}"
REGION="${AWS_REGION:?AWS_REGION is required}"

echo "================================================="
echo "Cleaning leftovers for:"
echo "ENV          = $ENV"
echo "CLUSTER      = $CLUSTER_NAME"
echo "REGION       = $REGION"
echo "================================================="

# Safety guard
if [[ "$ENV" == "prod" || "$ENV" == "production" ]]; then
  echo "❌ PRODUCTION DETECTED - ABORTING CLEANUP"
  exit 1
fi

############################################
# 1. ENIs (2-TIER SAFE FILTER)
############################################

echo "Checking ENIs..."

# -------------------------
# Tier 1: EKS-native tags (Better tags)
# -------------------------
ENIS=$(aws ec2 describe-network-interfaces \
  --region "$REGION" \
  --filters \
    "Name=status,Values=available" \
    "Name=tag:cluster.k8s.amazonaws.com/name,Values=$CLUSTER_NAME" \
    "Name=tag:eks:eni:owner,Values=amazon-vpc-cni" \
  --query "NetworkInterfaces[].NetworkInterfaceId" \
  --output text || true)

# -------------------------
# Tier 2: fallback (node-based identity)
# -------------------------
if [[ -z "${ENIS// }" ]]; then
  echo "[First try] ENI matched NONE, using node-instance fallback to also check..."

  # get instance IDs from cluster nodes
  INSTANCE_IDS=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:eks:cluster-name,Values=$CLUSTER_NAME" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text || true)

  if [[ -n "${INSTANCE_IDS// }" ]]; then
    ENIS=$(aws ec2 describe-network-interfaces \
      --region "$REGION" \
      --filters \
        "Name=status,Values=available" \
        "Name=attachment.instance-id,Values=$INSTANCE_IDS" \
      --query "NetworkInterfaces[].NetworkInterfaceId" \
      --output text || true)
  fi
fi

if [[ -n "${ENIS// }" ]]; then
  for eni in $ENIS; do
    echo "Deleting ENI: $eni"
    aws ec2 delete-network-interface \
      --region "$REGION" \
      --network-interface-id "$eni" || true
  done
else
  echo "✅ No ENIs found"
fi


############################################
# 2. LOAD BALANCERS
############################################

echo "Checking Load Balancers..."

LBS=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[?Tags[?Key=='cluster_name' && Value=='$CLUSTER_NAME']].LoadBalancerArn" \
  --output text || true)

if [[ -z "${LBS// }" ]]; then
  LBS=$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn" \
    --output text || true)
fi

if [[ -n "${LBS// }" ]]; then
  for lb in $LBS; do
    echo "Deleting LB: $lb"
    aws elbv2 delete-load-balancer \
      --region "$REGION" \
      --load-balancer-arn "$lb" || true
  done
else
  echo "✅ No Load Balancers found"
fi


############################################
# 3. TARGET GROUPS
############################################

echo "Checking Target Groups..."

TGS=$(aws elbv2 describe-target-groups \
  --region "$REGION" \
  --query "TargetGroups[?contains(TargetGroupName, '$CLUSTER_NAME')].TargetGroupArn" \
  --output text || true)

if [[ -n "${TGS// }" ]]; then
  for tg in $TGS; do
    echo "Deleting Target Group: $tg"
    aws elbv2 delete-target-group \
      --region "$REGION" \
      --target-group-arn "$tg" || true
  done
else
  echo "✅ No Target Groups found"
fi


############################################
# 4. EFS CLEANUP
############################################

echo "Checking EFS..."

EFS_LIST=$(aws efs describe-file-systems \
  --region "$REGION" \
  --query "FileSystems[?Tags[?Key=='cluster_name' && Value=='$CLUSTER_NAME']].FileSystemId" \
  --output text || true)

if [[ -n "${EFS_LIST// }" ]]; then
  for fs in $EFS_LIST; do
    echo "Found EFS: $fs"

    MTs=$(aws efs describe-mount-targets \
      --region "$REGION" \
      --file-system-id "$fs" \
      --query "MountTargets[*].MountTargetId" \
      --output text || true)

    for mt in $MTs; do
      echo "Deleting Mount Target: $mt"
      aws efs delete-mount-target \
        --region "$REGION" \
        --mount-target-id "$mt" || true
    done
  done
else
  echo "✅ No EFS systems found"
fi


############################################
# FINAL
############################################

echo "================================================="
echo "✅ Cleanup completed for $CLUSTER_NAME ($ENV)"
echo "================================================="

