#!/bin/bash
set -euo pipefail

BASE_FILE="app_default.yaml"

APP_CANDIDATES=("kubapp.yaml" "kubapp.yml")
SECRET_CANDIDATES=("secrets.yaml" "secrets.yml" "secret.yaml" "secret.yml")

APP_FILE=""
SECRET_FILE=""

# -------------------------
# Resolve app file
# -------------------------
for f in "${APP_CANDIDATES[@]}"; do
  [[ -f "$f" ]] && APP_FILE="$f" && break
done

echo NO_APP_FILE="false" >> "$GITHUB_ENV"

[[ -z "$APP_FILE" ]] && {
  echo "ℹ️ Using default app config"
  APP_FILE="$BASE_FILE"
  echo NO_APP_FILE="true" >> "$GITHUB_ENV"
}

# -------------------------
# Resolve secret file (optional)
# -------------------------
for f in "${SECRET_CANDIDATES[@]}"; do
  [[ -f "$f" ]] && SECRET_FILE="$f" && break
done

echo "Using config: $APP_FILE"

# -------------------------
# Extract values
# -------------------------
SERVICE=$(yq e '.service.name' "$APP_FILE")
PORT=$(yq e '.app.port' "$APP_FILE")
ENV=$(yq e '.deploy.env' "$APP_FILE")

[[ "$SERVICE" != "null" && -n "$SERVICE" ]] || {
  echo "❌ service.name missing"
  exit 1
}

# -------------------------
# Runtime env export
# -------------------------
yq e '.runtime.env // {} | to_entries[] | "\(.key)=\(.value)"' "$APP_FILE" \
| while IFS= read -r line; do
  echo "$line" >> "$GITHUB_ENV"
done

# -------------------------
# Secrets
# -------------------------
if [[ -n "$SECRET_FILE" && -s "$SECRET_FILE" ]]; then
  echo "Loading encrypted secrets..."

  if grep -q "sops" "$SECRET_FILE"; then
    echo "Detected SOPS-encrypted file, decrypting..."

    DECRYPTED=$(sops -d "$SECRET_FILE")

    echo "$DECRYPTED" \
    | yq e '.runtime.secrets // {} | to_entries[] | "\(.key)=\(.value)"' - \
    | while IFS= read -r line; do
        echo "$line" >> "$GITHUB_ENV"
      done

  else
    echo "Plain secrets file detected"

    yq e '.runtime.secrets // {} | to_entries[] | "\(.key)=\(.value)"' "$SECRET_FILE" \
    | while IFS= read -r line; do
        echo "$line" >> "$GITHUB_ENV"
      done
  fi

  echo "NO_SECRET_FILE=false" >> "$GITHUB_ENV"
else
  echo "ℹ️  No secrets file found"
  echo "NO_SECRET_FILE=true" >> "$GITHUB_ENV"
fi

# -------------------------
# Core exports
# -------------------------
{
  echo "SERVICE=$SERVICE"
  echo "PORT=$PORT"
  echo "ENV=$ENV"
} >> "$GITHUB_ENV"

echo "✅ Deployment context ready"
