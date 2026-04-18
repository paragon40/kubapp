#!/usr/bin/env bash
set -euo pipefail

echo "Cleaning Terraform artifacts..."

find iac -type f \( \
  -name "*.enc.yaml" -o \
  -name "*.enc.json" -o \
  -name "*.json" \
\) -delete

find iac -type f -name "secret-*.yaml" -delete

echo "Done"
