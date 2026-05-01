#!/bin/bash
set -euo pipefail

# =========================================
# Ingress Service Manager (ADD / REMOVE)
# Backward compatible:
#   register_new_svc.sh <service> <env>
#   register_new_svc.sh add <service> <env>
#   register_new_svc.sh remove <service> <env>
# =========================================

ACTION="${1:-}"
SERVICE_NAME="${2:-}"
ENV="${3:-dev}"

VALUES_FILE="gitops/ingress/${ENV}/values.yaml"

# -----------------------------------------
# Normalize legacy usage
# -----------------------------------------
if [[ -z "$SERVICE_NAME" ]]; then
  echo "Usage:"
  echo "  $0 <service> [env]"
  echo "  $0 add <service> [env]"
  echo "  $0 remove <service> [env]"
  exit 1
fi

# If first arg is a service (legacy mode)
if [[ "$ACTION" != "add" && "$ACTION" != "remove" ]]; then
  ENV="${2:-dev}"
  SERVICE_NAME="$ACTION"
  ACTION="add"
fi

echo "================================="
echo "ACTION : $ACTION"
echo "SERVICE: $SERVICE_NAME"
echo "ENV    : $ENV"
echo "FILE   : $VALUES_FILE"
echo "================================="

# -----------------------------------------
# Preconditions
# -----------------------------------------
command -v yq >/dev/null 2>&1 || {
  echo "yq is required"
  exit 1
}

[[ -f "$VALUES_FILE" ]] || {
  echo "Ingress file not found: $VALUES_FILE"
  exit 1
}

# ensure services exists
if ! yq e '.services' "$VALUES_FILE" >/dev/null 2>&1; then
  yq e '.services = []' -i "$VALUES_FILE"
fi

# -----------------------------------------
# ADD SERVICE
# -----------------------------------------
add_service() {
  EXISTS=$(yq e ".services[].name == \"$SERVICE_NAME\"" "$VALUES_FILE" | grep -c true || true)

  if [[ "$EXISTS" -gt 0 ]]; then
    echo "Service already exists: $SERVICE_NAME"
    return 0
  fi

  echo "Adding service: $SERVICE_NAME"

  yq e -i ".services += [{\"name\": \"$SERVICE_NAME\"}]" "$VALUES_FILE"

  echo "Service added"
}

# -----------------------------------------
# REMOVE SERVICE
# -----------------------------------------
remove_service() {
  EXISTS=$(yq e ".services[].name == \"$SERVICE_NAME\"" "$VALUES_FILE" | grep -c true || true)

  if [[ "$EXISTS" -eq 0 ]]; then
    echo "Service not found: $SERVICE_NAME"
    return 0
  fi

  echo "Removing service: $SERVICE_NAME"

  yq e -i ".services |= map(select(.name != \"$SERVICE_NAME\"))" "$VALUES_FILE"

  echo "Service removed"
}

# -----------------------------------------
# ROUTER
# -----------------------------------------
case "$ACTION" in
  add)
    add_service
    ;;
  remove)
    remove_service
    ;;
  *)
    echo "Invalid action: $ACTION"
    exit 1
    ;;
esac

echo
echo "Updated ingress:"
echo "---------------------------------"
cat "$VALUES_FILE"
echo "---------------------------------"
