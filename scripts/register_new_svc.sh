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
DOMAIN="${DOMAIN:-kubapp.rundailytest.online}"

VALUES_FILE="gitops/ingress/${ENV}/values.yaml"
TMP_FILE="/tmp/ingress-values-${ENV}.yaml"

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
echo "TMP    : $TMP_FILE"
echo "================================="

# -----------------------------------------
# Preconditions
# -----------------------------------------
sanitize() {
  echo "$1" | tr '_' '-' | tr '[:upper:]' '[:lower:]'
}

command -v yq >/dev/null 2>&1 || {
  echo "yq is required"
  exit 1
}

[[ -f "$VALUES_FILE" ]] || {
  echo "Ingress file not found: $VALUES_FILE"
  exit 1
}

# -----------------------------------------
# BOOTSTRAP TEMP STATE (REBUILD MODEL)
# -----------------------------------------
cp "$VALUES_FILE" "$TMP_FILE"

yq e -i "
  .ingress.baseDomain = \"${DOMAIN}\"
" "$TMP_FILE"

# ensure schema exists
yq e -i '
  .services = (.services // [])
' "$TMP_FILE"

# normalize existing entries (safe migration)
yq e -i '
  .services |= map(
    .enabled = (.enabled // true) |
    .port = (.port // 80)
  )
' "$TMP_FILE"

SERVICE_NAME="$(sanitize "$SERVICE_NAME")"

# -----------------------------------------
# ADD SERVICE
# -----------------------------------------
add_service() {
  EXISTS=$(yq e ".services[] | select(.name == \"$SERVICE_NAME\")" "$TMP_FILE" | wc -l || true)

  if [[ "$EXISTS" -gt 0 ]]; then
    echo "Service already exists: $SERVICE_NAME"
    return 0
  fi

  echo "Adding service: $SERVICE_NAME"

  yq e -i ".services += [{
    name: \"$SERVICE_NAME\",
    port: 80,
    enabled: true
  }]" "$TMP_FILE"

  echo "Service added"
}

# -----------------------------------------
# REMOVE SERVICE
# -----------------------------------------
remove_service() {
  EXISTS=$(yq e ".services[] | select(.name == \"$SERVICE_NAME\")" "$TMP_FILE" | wc -l || true)

  if [[ "$EXISTS" -eq 0 ]]; then
    echo "Service not found: $SERVICE_NAME"
    return 0
  fi

  echo "Removing service: $SERVICE_NAME"

  yq e -i ".services |= map(select(.name != \"$SERVICE_NAME\"))" "$TMP_FILE"

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

# -----------------------------------------
# VALIDATION (IMPORTANT SAFETY LAYER)
# -----------------------------------------
echo "Validating generated YAML..."

yq e '.' "$TMP_FILE" >/dev/null || {
  echo "Invalid YAML generated"
  exit 1
}

# -----------------------------------------
# ATOMIC REPLACE (FINAL COMMIT STEP)
# -----------------------------------------
echo "Applying changes atomically..."

cp "$VALUES_FILE" "${VALUES_FILE}.bak"
mv "$TMP_FILE" "$VALUES_FILE"

echo "Update complete"
echo
echo "Updated ingress:"
echo "---------------------------------"
cat "$VALUES_FILE"
echo "---------------------------------"
