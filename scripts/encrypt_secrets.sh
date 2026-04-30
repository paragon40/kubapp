#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../iac" && pwd)"
STACKS=("infra" "k8s")

ENV="${1:-dev}"   # dev | prod | all

echo "Root is $ROOT"

# =========================
# LOAD SETUP FUNCTIONS
# =========================
SETUP="./setup_sops.sh"
SETUP1="scripts/setup_sops.sh"
if [[ -f "$SETUP" ]]; then
  echo "Sourcing $SETUP"
  source "$SETUP"
elif [[ -f "$SETUP1" ]]; then
  echo "Sourcing $SETUP1"
  source "$SETUP1"
else
  echo "❌ setup_sops.sh not found"
  exit 1
fi

echo "Checking prerequisites..."

install_sops
install_age
ensure_age_key

AGE_PUBLIC_KEY=$(get_age_public_key)

if [[ -z "$AGE_PUBLIC_KEY" ]]; then
  echo "❌ Could not extract AGE public key"
  exit 1
fi

echo " Using AGE key: $AGE_PUBLIC_KEY"

# =========================
# ENV SELECTION
# =========================
get_envs() {
  case "$ENV" in
    dev)
      echo "dev"
      ;;
    prod)
      echo "prod"
      ;;
    all)
      echo "dev prod"
      ;;
    *)
      echo "❌ Invalid env: $ENV"
      exit 1
      ;;
  esac
}

# =========================
# ENCRYPT FUNCTION
# =========================
encrypt_tfvars() {
  local file="$1"
  local out="${file}.enc"

  echo "Encrypting: $file → $out"

  sops --encrypt \
    --age "$AGE_PUBLIC_KEY" \
    "$file" > "$out"
}

# =========================
# MAIN LOOP
# =========================
echo " Starting encryption for ENV=$ENV"

for env in $(get_envs); do
  echo ""
  echo "ENV: $env"

  for stack in "${STACKS[@]}"; do
    DIR="$ROOT/$stack/envs/$env"

    if [[ -d "$DIR" ]]; then
      echo "found"
    else
      echo "Not Found"
      continue
    fi

    echo "   → Stack: $stack"

    for tfvars in "$DIR"/*.tfvars; do
      [[ -f "$tfvars" ]] ||  continue
      encrypt_tfvars "$tfvars"
    done
  done
done


# =========================
# GITOPS SOPS ENCRYPTION
# =========================

GITOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../gitops/secrets" && pwd)"
BACKUP_DIR="$GITOPS_DIR/.backup"

echo " Starting GitOps encryption in: $GITOPS_DIR"

mkdir -p "$BACKUP_DIR"

[[ -d "$GITOPS_DIR" ]] || {
  echo "❌ Directory not found: $GITOPS_DIR"
  exit 1
}

shopt -s nullglob

found_files=false
valid_files=false

for file in "$GITOPS_DIR"/*.yaml "$GITOPS_DIR"/*.yml; do
  [[ -f "$file" ]] || continue
  found_files=true

  echo "➡ Processing: $file"

  # -------------------------
  # Detect already encrypted
  # -------------------------
  if grep -q '^sops:' "$file"; then
    echo "⏭ Already encrypted, skipping: $file"
    valid_files=true
    continue
  fi

  # -------------------------
  # Backup original
  # -------------------------
  backup_file="$BACKUP_DIR/$(basename "$file").bak"
  cp -f "$file" "$backup_file"
  echo " Backup: $backup_file"

  # -------------------------
  # Encrypt in-place
  # -------------------------
  if sops -e -i "$file"; then
    echo "✅ Encrypted: $file"
    valid_files=true
  else
    echo "❌ Failed: $file"
    echo "Restoring backup..."
    cp -f "$backup_file" "$file"
    exit 1
  fi

done

# -------------------------
# Final validation
# -------------------------
if [[ "$found_files" = false ]]; then
  echo "❌ No YAML files found"
  exit 1
fi

if [[ "$valid_files" = false ]]; then
  echo "❌ No valid encrypted files exist"
  exit 1
fi

echo ""
echo "✅ Encryption complete"
