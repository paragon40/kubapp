#!/usr/bin/env bash
set -euo pipefail

ROOT="../iac"
STACKS=("infra" "k8s")

ENV="${1:-dev}"   # default is dev only

# =========================
# LOAD SETUP FUNCTIONS
# =========================
SETUP="./setup_sops.sh"

if [[ -f "$SETUP" ]]; then
  source "$SETUP"
else
  if [[ -n "${GITHUB_ACTIONS:-}" || -n "${CI:-}" ]]; then
    echo "❌ setup_sops.sh missing in CI environment"
    exit 1
  fi

  echo "❌ setup_sops.sh not found"
  read -r -p "Continue anyway? (y/n): " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
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

echo "Using AGE key: $AGE_PUBLIC_KEY"

# =========================
# CONVERT TFVARS -> JSON
# =========================
convert_tfvars() {
  local tfvars="$1"
  local out="${tfvars%.tfvars}.json"

  echo "Converting: $tfvars → $out"

  tmpdir=$(mktemp -d)

  cat > "$tmpdir/main.tf" <<EOF
terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
    }
  }
}
EOF

  terraform -chdir="$tmpdir" init -input=false -no-color >/dev/null

  terraform -chdir="$tmpdir" plan \
    -var-file="$PWD/$tfvars" \
    -out="$tmpdir/plan.out" >/dev/null

  terraform -chdir="$tmpdir" show -json "$tmpdir/plan.out" > "$out"

  rm -rf "$tmpdir"
}

# =========================
# ENCRYPT
# =========================
encrypt_file() {
  local file="$1"
  local out="${file%.json}.enc.json"

  echo "Encrypting: $file → $out"

  sops --encrypt \
    --input-type json \
    --output-type json \
    --age "$AGE_PUBLIC_KEY" \
    "$file" > "$out"
}

# =========================
# ENV SELECTION LOGIC
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
# RUN
# =========================
echo "Starting encryption for ENV=$ENV"

for env in $(get_envs); do
  echo ""
  echo "ENV: $env"

  for stack in "${STACKS[@]}"; do
    for tf in "$ROOT/$stack/envs/$env.tfvars"; do
      [[ -f "$tf" ]] || continue

      convert_tfvars "$tf"

      json_file="${tf%.tfvars}.json"

      if [[ -f "$json_file" ]]; then
        encrypt_file "$json_file"
        rm -f "$json_file"
      fi
    done
  done
done

echo "Done"
