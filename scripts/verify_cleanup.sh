#!/usr/bin/env bash
set -euo pipefail

ENV="${ENV:?ENV required}"
CLUSTER_NAME="${CLUSTER_NAME:?CLUSTER_NAME required}"
REGION="${AWS_REGION:?AWS_REGION required}"

echo "Verifying cleanup for $CLUSTER_NAME ($ENV)"

fail=0

check() {
  name="$1"
  cmd="$2"

  echo "Checking $name..."
  result=$(eval "$cmd" || true)

  if [[ -n "$result" ]]; then
    echo "❌ $name still exists:"
    echo "$result"
    fail=1
  else
    echo "✅ $name clean"
  fi
}

# ENIs (tag-based)
check "ENIs" \
"aws ec2 describe-network-interfaces \
 --region $REGION \
 --filters Name=tag:cluster.k8s.amazonaws.com/name,Values=$CLUSTER_NAME \
 --query 'NetworkInterfaces[*].NetworkInterfaceId' \
 --output text"

# Load balancers
check "LoadBalancers" \
"aws elbv2 describe-load-balancers \
 --region $REGION \
 --query \"LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn\" \
 --output text"

# EFS
check "EFS" \
"aws efs describe-file-systems \
 --region $REGION \
 --query \"FileSystems[?contains(Name, '$CLUSTER_NAME')].FileSystemId\" \
 --output text"

if [[ "$fail" -eq 1 ]]; then
  echo "❌ Cluster not clean — aborting infra destroy"
  exit 1
fi

echo "✅ Cluster fully clean — safe for infra destroy"

