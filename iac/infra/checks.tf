resource "null_resource" "k8s_destroy_safety_check" {

  provisioner "local-exec" {
    when = destroy

    command = <<EOT
set -e

echo "Checking for leftover ENIs..."
ENIS=$(aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=${var.vpc_id}" \
  --query "NetworkInterfaces[*].NetworkInterfaceId" \
  --output text)

if [ -n "$ENIS" ]; then
  echo "❌ ENIs still exist:"
  echo "$ENIS"
  exit 1
fi

echo "Checking Load Balancers..."
LBS=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[*].LoadBalancerArn" \
  --output text)

if [ -n "$LBS" ]; then
  echo "❌ Load balancers still exist"
  exit 1
fi

echo "Checking EFS mount targets..."
EFS=$(aws efs describe-mount-targets \
  --query "MountTargets[*].MountTargetId" \
  --output text)

if [ -n "$EFS" ]; then
  echo "❌ EFS mount targets still exist"
  exit 1
fi

echo "✅ AWS cleanup verified — safe to destroy infra"
EOT
  }
}

