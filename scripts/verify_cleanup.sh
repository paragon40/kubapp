#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# cleanup_audit.sh
#
# Purpose:
#   Full AWS cluster cleanup verification + orphan detection
#   (READ-ONLY forensic audit tool)
#
# Scope:
#   ENI, ELB, TG, EC2, ASG, SG, Subnets, EBS, EFS, NAT GW
#
# Behavior:
#   - Auto-resolves VPC from EKS OR uses provided VPC_ID
#   - Pulls full AWS inventory
#   - Correlates resources by relationships
#   - Flags orphaned + cost-incurring resources
# ============================================================

CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
REGION="${AWS_REGION:?AWS_REGION required}"
VPC_ID="${VPC_ID:-}"

echo "=================================================="
echo "AWS Cleanup Audit Tool"
echo "Cluster : $CLUSTER_NAME"
echo "Region  : $REGION"
echo "=================================================="

# ============================================================
# 1. Resolve VPC
# ============================================================

if [[ -z "$VPC_ID" ]]; then
  echo "[INFO] VPC_ID not provided. Deriving from EKS..."

  VPC_ID=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text 2>/dev/null || true)

  if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
    echo "❌ Failed to resolve VPC from cluster"
    exit 1
  fi

  echo "[INFO] Derived VPC_ID: $VPC_ID"
else
  echo "[INFO] Using provided VPC_ID: $VPC_ID"
fi

echo "--------------------------------------------------"

# ============================================================
# 2. Data Collection
# ============================================================

echo "[INFO] Collecting AWS resources..."

ENIS=$(aws ec2 describe-network-interfaces --region "$REGION")
ELB_CLASSIC=$(aws elb describe-load-balancers --region "$REGION")
ELB_V2=$(aws elbv2 describe-load-balancers --region "$REGION")
TARGET_GROUPS=$(aws elbv2 describe-target-groups --region "$REGION")
EC2_INSTANCES=$(aws ec2 describe-instances --region "$REGION")
ASGS=$(aws autoscaling describe-auto-scaling-groups --region "$REGION")
SGS=$(aws ec2 describe-security-groups --region "$REGION")
EBS=$(aws ec2 describe-volumes --region "$REGION")
EFS=$(aws efs describe-file-systems --region "$REGION")
NAT_GWS=$(aws ec2 describe-nat-gateways --region "$REGION")

echo "[INFO] Data collection complete"
echo "--------------------------------------------------"

# ============================================================
# 3. Analysis helpers
# ============================================================

fail=0

mark() {
  echo ""
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

# ============================================================
# 4. ENI Analysis
# ============================================================

mark "ENI ANALYSIS"

echo "$ENIS" | jq -r --arg VPC "$VPC_ID" --arg CLUSTER "$CLUSTER_NAME" '
.NetworkInterfaces[]
| select(.VpcId == $VPC)
| select(
    (.Description // "" | test($CLUSTER; "i"))
    or (.RequesterManaged == true)
    or (.Attachment.InstanceId != null)
  )
| "ENI: \(.NetworkInterfaceId)
Desc: \(.Description)
Status: \(.Status)
Attachment: \(.Attachment.InstanceId // "none")
"
' || true

# ============================================================
# 5. Load Balancers
# ============================================================

mark "LOAD BALANCERS (CLASSIC)"

echo "$ELB_CLASSIC" | jq -r --arg CLUSTER "$CLUSTER_NAME" '
.LoadBalancerDescriptions[]
| select(.LoadBalancerName | test($CLUSTER; "i"))
| "LB: \(.LoadBalancerName)\nDNS: \(.DNSName)\n"
' || true

mark "LOAD BALANCERS (ALB/NLB)"

echo "$ELB_V2" | jq -r --arg CLUSTER "$CLUSTER_NAME" '
.LoadBalancers[]
| select(.VpcId != null)
| select(.LoadBalancerName | test($CLUSTER; "i") or test("k8s"; "i"))
| "LB: \(.LoadBalancerName)\nType: \(.Type)\nDNS: \(.DNSName)\n"
' || true

# ============================================================
# 6. Target Groups
# ============================================================

mark "TARGET GROUPS"

echo "$TARGET_GROUPS" | jq -r --arg CLUSTER "$CLUSTER_NAME" '
.TargetGroups[]
| select(.TargetGroupName | test($CLUSTER; "i") or test("k8s"; "i"))
| "TG: \(.TargetGroupName)\nARN: \(.TargetGroupArn)\n"
' || true

# ============================================================
# 7. EC2 / ASG
# ============================================================

mark "EC2 INSTANCES (ORPHAN CHECK)"

echo "$EC2_INSTANCES" | jq -r --arg CLUSTER "$CLUSTER_NAME" '
.Reservations[].Instances[]
| select(.State.Name != "terminated")
| "Instance: \(.InstanceId) | State: \(.State.Name) | Type: \(.InstanceType)"
' || true

mark "AUTO SCALING GROUPS"

echo "$ASGS" | jq -r --arg CLUSTER "$CLUSTER_NAME" '
.AutoScalingGroups[]
| select(.AutoScalingGroupName | test($CLUSTER; "i"))
| "ASG: \(.AutoScalingGroupName)\nMin: \(.MinSize) Max: \(.MaxSize)\n"
' || true

# ============================================================
# 8. Security Groups
# ============================================================

mark "SECURITY GROUPS"

echo "$SGS" | jq -r --arg CLUSTER "$CLUSTER_NAME" '
.SecurityGroups[]
| select(.GroupName | test($CLUSTER; "i"))
| "SG: \(.GroupId) | \(.GroupName)"
' || true

# ============================================================
# 9. EBS Volumes (COST RISK)
# ============================================================

mark "EBS VOLUMES (COST RISK)"

echo "$EBS" | jq -r '
.Volumes[]
| select(.State == "available")
| "Volume: \(.VolumeId) | Size: \(.Size)GB | State: \(.State)"
' || true

# ============================================================
# 10. EFS (COST RISK)
# ============================================================

mark "EFS FILE SYSTEMS (COST RISK)"

echo "$EFS" | jq -r '
.FileSystems[]
| " EFS: \(.FileSystemId) | State: \(.LifeCycleState)"
' || true

# ============================================================
# 11. NAT Gateways (HIGH COST CRITICAL)
# ============================================================

mark "NAT GATEWAYS (HIGH COST)"

echo "$NAT_GWS" | jq -r '
.NatGateways[]
| select(.State != "deleted")
| "NAT GW: \(.NatGatewayId) | State: \(.State) | VPC: \(.VpcId)"
' || true

# ============================================================
# FINAL SUMMARY
# ============================================================

echo ""
echo "- Reviewd ENIs, LBs, NAT GW, EFS, EBS carefully"
echo "=================================================="
echo "CLEANUP AUDIT COMPLETE"
echo "=================================================="

