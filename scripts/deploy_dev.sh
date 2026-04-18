#!/usr/bin/env bash
set -euo pipefail

SERVICE=$1

echo "Deploying DEV for $SERVICE"

argocd app sync ${SERVICE}-dev
argocd app wait ${SERVICE}-dev --health
