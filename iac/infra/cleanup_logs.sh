#!/bin/bash

set -e

echo "Cleaning EKS CloudWatch log groups..."

if aws logs delete-log-group --log-group-name /aws/eks/kubapp/cluster; then
  echo "/aws/eks/kubapp/cluster delected"
fi

if aws logs delete-log-group --log-group-name /aws/vpc/kubapp-flowlogs; then
  echo "/aws/vpc/kubapp-flowlogs deleted"
fi


echo "✅ Cleanup done"
