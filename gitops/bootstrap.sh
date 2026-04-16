#!/usr/bin/env bash

APPS=("user" "admin")
ENVS=("dev" "prod")

for app in "${APPS[@]}"; do
  for env in "${ENVS[@]}"; do

    mkdir -p gitops/apps/$app/overlays/$env

    cat <<EOF > gitops/apps/$app/overlays/$env/values.yaml
image:
  repository: placeholder
  tag: latest
EOF

  done
done

echo "GitOps env structure created"
