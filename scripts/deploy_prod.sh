#!/usr/bin/env bash
set -euo pipefail

SERVICE=$1

echo "Deploying PROD for $SERVICE"

argocd app sync ${SERVICE}-prod
argocd app wait ${SERVICE}-prod --health
