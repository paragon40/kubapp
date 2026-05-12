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
BACKEND_SERVICE="${BACKEND_SERVICE:-}"

VALUES_FILE="gitops/ingress/${ENV}/values.yaml"
TMP_FILE="/tmp/ingress-values-${ENV}.yaml"
BACKEND_FILE="gitops/ingress/${ENV}/monitoring.yaml"

# -----------------------------------------
# Normalize legacy usage
# -----------------------------------------
if [[ "$ACTION" != "add" && "$ACTION" != "remove" ]]; then
  ENV="${2:-dev}"
  SERVICE_NAME="$ACTION"
  ACTION="add"
fi

if [[ -z "$SERVICE_NAME" ]]; then
  echo "Usage:"
  echo "  $0 <service> [env]"
  echo "  $0 add <service> [env]"
  echo "  $0 remove <service> [env]"
  exit 1
fi

# -----------------------------------------
# Required variables
# -----------------------------------------
if [[ "$ACTION" == "add" ]]; then
  ARR=("ACTION" "SERVICE_NAME" "ENV" "DOMAIN" "CERT_ARN" "PORT" "VALUES_FILE")
else
  ARR=("ACTION" "SERVICE_NAME" "ENV" "VALUES_FILE")
fi

for var in "${ARR[@]}"; do
  value="${!var}"

  if [[ -z "$value" ]]; then
    echo "❌ $var required"
    exit 1
  fi

  export "$var=$value"
done

# Validate port only for add
if [[ "$ACTION" == "add" ]]; then
  [[ "$PORT" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 ]] || {
    echo "❌ Invalid PORT: $PORT"
    exit 1
  }
fi

echo "================================="
echo "ACTION : $ACTION"
echo "SERVICE: $SERVICE_NAME"
if [[ -n "$BACKEND_SERVICE" ]]; then
  echo "BACKEND SERVICE: $BACKEND_SERVICE"
  USE_FILE="$BACKEND_FILE"
  NS="monitoring"
else
  USE_FILE="$VALUES_FILE"
  NS="$ENV"
fi
echo "ENV    : $ENV"
echo "FILE   : $USE_FILE"
echo "TMP    : $TMP_FILE"
echo "================================="

# -----------------------------------------
# Preconditions
# -----------------------------------------
sanitize() {
  echo "$1" | tr '_' '-' | tr '[:upper:]' '[:lower:]'
}

command -v yq >/dev/null 2>&1 || { echo "yq is required"; exit 1; }

[[ -f "$USE_FILE" ]] || {
  echo "Ingress file not found: $USE_FILE"
  exit 1
}

# -----------------------------------------
# BOOTSTRAP TEMP STATE
# -----------------------------------------
cp "$USE_FILE" "$TMP_FILE"

# -----------------------------------------
# INGRESS DYNAMIC CONFIGURATION (ADD ONLY)
# -----------------------------------------
if [[ "$ACTION" == "add" ]]; then
  yq e -i '
    .ingress.baseDomain = strenv(DOMAIN)
    | .ingress.certificateArn = strenv(CERT_ARN)
    | .ingress.name = (.ingress.name // ("kubapp-" + strenv(NS) + "-alb"))
    | .ingress.className = (.ingress.className // "alb")
    | .ingress.enableSubdomainRouting = (.ingress.enableSubdomainRouting // true)
    | .ingress.annotations.listenPorts = [
        {"HTTP": 80},
        {"HTTPS": 443}
      ]
  ' "$TMP_FILE"

  if yq e '.ingress.annotations.listenPorts | type' "$TMP_FILE" | grep -q '!!str'; then
    echo "❌ listenPorts must NOT be a string"
    exit 1
  fi
fi

# Ensure services array exists
yq e -i '.services = (.services // [])' "$TMP_FILE"

# Normalize service entries
yq e -i '
  .services |= map(
    .enabled = (.enabled // true) |
    .port = (.port // 80)
  )
' "$TMP_FILE"

# Keep only enabled services
yq e -i '.services |= map(select(.enabled == true))' "$TMP_FILE"

SERVICE_NAME="$(sanitize "$SERVICE_NAME")"
export SERVICE_NAME

# =========================================
# VALIDATION FUNCTIONS
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

  TYPE=$(yq e '.ingress.annotations.listenPorts | type' "$TMP_FILE")

  if [[ "$TYPE" != "!!seq" ]]; then
    echo "❌ listenPorts must be a YAML array"
    exit 1
  fi

  HTTP=$(yq e '.ingress.annotations.listenPorts[] | select(has("HTTP")) | .HTTP' "$TMP_FILE" | head -n1)
  HTTPS=$(yq e '.ingress.annotations.listenPorts[] | select(has("HTTPS")) | .HTTPS' "$TMP_FILE" | head -n1)

  [[ "$HTTP" == "80" ]] || {
    echo "❌ HTTP must be 80"
    exit 1
  }

  [[ "$HTTPS" == "443" ]] || {
    echo "❌ HTTPS must be 443"
    exit 1
  }

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
  EXISTS=$(yq e ".services[] | select(.name == strenv(SERVICE_NAME)) | .name" "$TMP_FILE" | wc -l)

  if [[ "$EXISTS" -gt 0 ]]; then
    echo "Service already exists: $SERVICE_NAME"
    return 0
  fi

  echo "Adding service: $SERVICE_NAME"

  if [[ -n "$BACKEND_SERVICE" ]]; then
    yq e -i '.services += [{
      "name": strenv(SERVICE_NAME),
      "port": env(PORT),
      "enabled": true,
      "backend": {
        "service": strenv(BACKEND_SERVICE)
      }
    }]' "$TMP_FILE"
  else
    yq e -i '.services += [{
      "name": strenv(SERVICE_NAME),
      "port": env(PORT),
      "enabled": true
    }]' "$TMP_FILE"
  fi
}

remove_service() {
  EXISTS=$(yq e ".services[] | select(.name == strenv(SERVICE_NAME)) | .name" "$TMP_FILE" | wc -l)

  if [[ "$EXISTS" -eq 0 ]]; then
    echo "Service not found: $SERVICE_NAME"
    return 0
  fi

  echo "Removing service: $SERVICE_NAME"

  yq e -i '
    .services |= map(select(.name != strenv(SERVICE_NAME)))
  ' "$TMP_FILE"
}

# =========================================
# EXECUTION FLOW
# =========================================

case "$ACTION" in
  add) add_service ;;
  remove) remove_service ;;
  *) echo "Invalid action"; exit 1 ;;
esac

# =========================================
# VALIDATION
# =========================================

validate_schema
validate_listen_ports
validate_https_requirements

echo "Running YAML validation..."
yq e '.' "$TMP_FILE" >/dev/null

echo "Running final structural validation..."

yq e '
  .ingress.baseDomain != null and
  .ingress.name != null and
  (.services | length > 0)
' "$TMP_FILE" | grep -q true || {
  echo "❌ Ingress schema invalid"
  exit 1
}

# =========================================
# ATOMIC APPLY
# =========================================

echo "Applying changes atomically..."


cp "$USE_FILE" "${USE_FILE}.bak"
mv "$TMP_FILE" "$USE_FILE"

echo "Update complete"
echo "---------------------------------"
cat "$USE_FILE"
echo "---------------------------------"
