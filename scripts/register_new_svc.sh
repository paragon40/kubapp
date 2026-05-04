#!/bin/bash
set -euo pipefail

# =========================================
# Ingress Service Manager (ADD / REMOVE)
#   register_new_svc.sh <service> <env>
#   register_new_svc.sh add <service> <env>
#   register_new_svc.sh remove <service> <env>
# =========================================

ACTION="${1:-}"
SERVICE_NAME="${2:-}"
ENV="${3:-dev}"
DOMAIN="${DOMAIN:-}"
CERT_ARN="${CERT_ARN:-}"
PORT="${SERVICE_PORT:-80}"

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

command -v yq >/dev/null 2>&1 || { echo "yq is required"; exit 1; }

[[ -f "$VALUES_FILE" ]] || { echo "Ingress file not found: $VALUES_FILE"; exit 1; }

# -----------------------------------------
# BOOTSTRAP TEMP STATE
# -----------------------------------------
cp "$VALUES_FILE" "$TMP_FILE"

# -------------------------------
# INGRESS DYNAMIC CONFIGURATION
# -------------------------------
yq e -i '
  .ingress.baseDomain = env(DOMAIN)
  | .ingress.certificateArn = env(CERT_ARN)
  | .ingress.name = (.ingress.name // ("kubapp-" + env(ENV) + "-alb"))
  | .ingress.className = (.ingress.className // "alb")
  | .ingress.enableSubdomainRouting = (.ingress.enableSubdomainRouting // true)
' "$TMP_FILE"

# ensure services array
yq e -i '.services = (.services // [])' "$TMP_FILE"

# normalize
yq e -i '
  .services |= map(
    .enabled = (.enabled // true) |
    .port = (.port // 80)
  )
' "$TMP_FILE"

# filter enabled only
yq e -i '.services |= map(select(.enabled == true))' "$TMP_FILE"

SERVICE_NAME="$(sanitize "$SERVICE_NAME")"

# =========================================
# VALIDATION FUNCTIONS (CLEAN SECTION)
# =========================================

validate_schema() {
  echo "Validating ingress schema..."

  yq e '.ingress.baseDomain' "$TMP_FILE" | grep -q . || {
    echo "❌ baseDomain missing"
    exit 1
  }

  yq e '.ingress.name' "$TMP_FILE" | grep -q . || {
    echo "❌ ingress name missing"
    exit 1
  }

  [[ $(yq e '.services | length' "$TMP_FILE") -gt 0 ]] || {
    echo "❌ No services defined"
    exit 1
  }
}

validate_listen_ports() {
  echo "Validating listenPorts..."

  HTTP=$(yq e '.ingress.annotations.listenPorts[] | select(has("HTTP")) | .HTTP' "$TMP_FILE" 2>/dev/null || true)
  HTTPS=$(yq e '.ingress.annotations.listenPorts[] | select(has("HTTPS")) | .HTTPS' "$TMP_FILE" 2>/dev/null || true)

  if [[ -n "$HTTP" && "$HTTP" != "80" ]]; then
    echo "❌ HTTP must be 80"
    exit 1
  fi

  if [[ -n "$HTTPS" && "$HTTPS" != "443" ]]; then
    echo "❌ HTTPS must be 443"
    exit 1
  fi

  echo "✅ listenPorts valid"
}

validate_https_requirements() {
  echo "Validating HTTPS config..."

  if yq e '.ingress.annotations.listenPorts[] | has("HTTPS")' "$TMP_FILE" | grep -q true; then
    yq e '.ingress.certificateArn' "$TMP_FILE" | grep -q . || {
      echo "❌ HTTPS enabled but certificateArn missing"
      exit 1
    }
  fi
}

# =========================================
# SERVICE OPERATIONS
# =========================================

add_service() {
  EXISTS=$(yq e ".services[] | select(.name == \"$SERVICE_NAME\")" "$TMP_FILE" | wc -l || true)

  [[ "$EXISTS" -gt 0 ]] && {
    echo "Service already exists: $SERVICE_NAME"
    return 0
  }

  echo "Adding service: $SERVICE_NAME"

  yq e -i ".services += [{
    name: \"$SERVICE_NAME\",
    port: $PORT,
    enabled: true
  }]" "$TMP_FILE"
}

remove_service() {
  EXISTS=$(yq e ".services[] | select(.name == \"$SERVICE_NAME\")" "$TMP_FILE" | wc -l || true)

  [[ "$EXISTS" -eq 0 ]] && {
    echo "Service not found: $SERVICE_NAME"
    return 0
  }

  echo "Removing service: $SERVICE_NAME"

  yq e -i ".services |= map(select(.name != \"$SERVICE_NAME\"))" "$TMP_FILE"
}

# =========================================
# EXECUTION FLOW
# =========================================

case "$ACTION" in
  add) add_service ;;
  remove) remove_service ;;
  *) echo "Invalid action"; exit 1 ;;
esac

# -----------------------------------------
# VALIDATION PIPELINE (ORDERED)
# -----------------------------------------
validate_schema
validate_listen_ports
validate_https_requirements

echo "Running YAML validation..."
yq e '.' "$TMP_FILE" >/dev/null || {
  echo "Invalid YAML generated"
  exit 1
}

echo "Running final structural validation..."

yq e '
.ingress.baseDomain != null and
.ingress.name != null and
.services | length > 0
' "$TMP_FILE" | grep -q true || {
  echo "❌ Ingress schema invalid"
  exit 1
}

# -----------------------------------------
# ATOMIC APPLY
# -----------------------------------------
echo "Applying changes atomically..."

cp "$VALUES_FILE" "${VALUES_FILE}.bak"
mv "$TMP_FILE" "$VALUES_FILE"

echo "Update complete"
echo "---------------------------------"
cat "$VALUES_FILE"
echo "---------------------------------"
