#!/bin/bash

arg="${1:-apply}"

echo "Starting... $arg"
terraform init
terraform fmt

apply() {
  terraform validate
  terraform plan
  echo ""
  echo "Applying now...."
  terraform apply --auto-approve
}

destroy() {
  echo ""
  echo "Destroying now...."
  terraform destroy --auto-approve
}

if [[ "$arg" == "destroy" ]]; then
  destroy
else
  apply
fi
