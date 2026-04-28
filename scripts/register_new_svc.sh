#!/bin/bash
set -euo pipefail

# =========================================
# Register new service into global ingress
# One ALB / One Global Ingress pattern
# =========================================

# -----------------------------------------
# Validate input
# -----------------------------------------
SCRIPT="${0:-}"
SERVICE_NAME="${1:-}"
ENV="${2:-dev}"
VALUES_FILE="gitops/ingress/${ENV}/values.yaml"

if [[ -z "$SERVICE_NAME" ]]; then
  echo "Usage:"
  echo "  ./scripts/$SCRIPT <service-name>"
  echo
  echo "Example:"
  echo "  ./scripts/$SCRIPT notification"
  exit 1
fi

echo "Registering service: $SERVICE_NAME"

# -----------------------------------------
# Validate values file exists
# -----------------------------------------
if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Ingress values file not found:"
  echo "  $VALUES_FILE"
  exit 1
fi

# -----------------------------------------
# Ensure yq exists
# -----------------------------------------
if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required but not installed"
  exit 1
fi

# -----------------------------------------
# Ensure services key exists
# -----------------------------------------
SERVICES_EXISTS=$(yq e '.services != null' "$VALUES_FILE")

if [[ "$SERVICES_EXISTS" != "true" ]]; then
  echo "Initializing services list..."
  yq e '.services = []' -i "$VALUES_FILE"
fi

# -----------------------------------------
# Prevent duplicate registration
# -----------------------------------------
EXISTS=$(yq e ".services[].name == \"$SERVICE_NAME\"" "$VALUES_FILE" | grep -c true || true)

if [[ "$EXISTS" -gt 0 ]]; then
  echo "Service already registered: $SERVICE_NAME"
  exit 0
fi

# -----------------------------------------
# Append new service
# -----------------------------------------
echo "Adding service to global ingress registry..."

yq e ".services += [{\"name\": \"$SERVICE_NAME\"}]" -i "$VALUES_FILE"

echo "Service successfully registered."

echo
echo "Updated file:"
echo "----------------------------------"
cat "$VALUES_FILE"
echo "----------------------------------"

echo
echo "Resulting routes:"
echo "Path route:"
echo "  https://kubapp.rundailytest.site/$SERVICE_NAME"

echo "Subdomain route:"
echo "  https://$SERVICE_NAME.kubapp.rundailytest.site"

echo
echo "Done."
