#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# RUNTIME + SECRET INJECTION (IDEMPOTENT + SAFE MERGE)
# =========================================================

ARTIFACT_FILE="${1:-}"

fail() {
  echo "❌ $1"
  exit 1
}

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

[[ -n "$ARTIFACT_FILE" ]] || fail "Usage: set_app_secret.sh <artifact-json>"
[[ -f "$ARTIFACT_FILE" ]] || fail "Artifact not found: $ARTIFACT_FILE"

require jq
require yq

SERVICE=$(jq -r '.service' "$ARTIFACT_FILE")
ENV=$(jq -r '.env' "$ARTIFACT_FILE")
CONTEXT=$(jq -r '.context' "$ARTIFACT_FILE")
NO_VARS=$(jq -r '.NO_VARS // true' "$ARTIFACT_FILE")
NO_SECRETS=$(jq -r '.NO_SECRETS // true' "$ARTIFACT_FILE")

TARGET_FILE="gitops/envs/$ENV/$SERVICE/values.yaml"

[[ -f "$TARGET_FILE" ]] || fail "values.yaml missing: $TARGET_FILE"

APP_FILE=""
SECRET_FILE=""

for f in "$CONTEXT/kubapp.yaml" "$CONTEXT/kubapp.yml"; do
  [[ -f "$f" ]] && APP_FILE="$f" && break
done

for f in \
  "$CONTEXT/secrets.yaml" \
  "$CONTEXT/secrets.yml" \
  "$CONTEXT/secret.yaml" \
  "$CONTEXT/secret.yml"
do
  [[ -f "$f" ]] && SECRET_FILE="$f" && break
done

echo "Preparing runtime injection for $SERVICE"

####################################################
# FULL RESET (TRUE IDEMPOTENCY)
####################################################
yq e '
  .env = {} |
  del(.runtime.env) |
  del(.runtime.secrets)
' -i "$TARGET_FILE"

####################################################
# RUNTIME ENV
####################################################
if [[ "$NO_VARS" == "false" && -n "$APP_FILE" ]]; then
  echo "Injecting runtime.env"

  TMP_ENV="/tmp/runtime-env.yaml"
  yq e '.runtime.env // {}' "$APP_FILE" > "$TMP_ENV"

  yq e '.env = load("'"$TMP_ENV"'")' -i "$TARGET_FILE"

  echo "✅ Runtime env applied (clean replace)"
else
  echo "ℹ️ No runtime env"
fi

####################################################
# SECRETS (SOPS SAFE FLOW)
####################################################
if [[ "$NO_SECRETS" == "false" && -n "$SECRET_FILE" ]]; then
  echo "Injecting secrets from: $SECRET_FILE"

  require sops

  # Validate encrypted file first (fail fast)
  sops -d "$SECRET_FILE" >/dev/null 2>&1 || fail "Secret decryption failed"

  TMP_SEC="/tmp/runtime-secrets.yaml"
  sops -d "$SECRET_FILE" > "$TMP_SEC"

  yq e '.runtime.secrets // {}' "$TMP_SEC" > /tmp/secret-values.yaml

  yq e '.env += load("/tmp/secret-values.yaml")' -i "$TARGET_FILE"

  echo "✅ Secrets applied safely"
else
  echo "ℹ️ No secrets"
fi

RUNTIME_HASH=$(yq e '.env | to_entries | sort_by(.key)' "$TARGET_FILE" | sha256sum | awk '{print $1}')
yq e -i ".meta.runtimeHash = \"$RUNTIME_HASH\"" "$TARGET_FILE"

echo "✅ Injection complete for $SERVICE"
