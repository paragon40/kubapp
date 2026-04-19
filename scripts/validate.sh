#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-dev}"

echo "=============================="
echo "🔍 SYSTEM VALIDATION STARTED"
echo "ENV: $ENV"
echo "=============================="

############################################
# HELPERS
############################################
fail() {
  echo "❌ $1"
  exit 1
}

check_file() {
  [[ -f "$1" ]] || fail "Missing file: $1"
}

check_dir() {
  [[ -d "$1" ]] || fail "Missing directory: $1"
}

############################################
# 1. REQUIRED TOOLS
############################################
echo "🔧 Checking required tools..."

TOOLS=(terraform sops age yq jq git)

for tool in "${TOOLS[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || fail "Missing tool: $tool"
done

echo "✔ Tools OK"

############################################
# 2. PROJECT STRUCTURE
############################################
echo "📁 Validating structure..."

# Core dirs
check_dir "iac"
check_dir "iac/infra"
check_dir "iac/k8s"
check_dir "gitops"
check_dir "scripts"

# Env dirs
for stack in infra k8s; do
  for env in dev prod; do
    check_dir "iac/$stack/envs/$env"
    check_file "iac/$stack/envs/$env/backend.hcl"
  done
done

echo "✔ Structure OK"

############################################
# 3. TERRAFORM VALIDATION
############################################
echo "📦 Validating Terraform..."

for stack in infra k8s; do
  pushd "iac/$stack" >/dev/null

  terraform init -backend=false >/dev/null
  terraform validate || fail "Terraform validation failed in $stack"

  popd >/dev/null
done

echo "✔ Terraform OK"

############################################
# 4. TFVARS + SOPS VALIDATION
############################################
echo "🔐 Validating secrets..."

for stack in infra k8s; do
  BASE="iac/$stack/envs/$ENV"

  # plain tfvars
  check_file "$BASE/${ENV}.tfvars"

  # encrypted (optional but expected)
  if [[ -f "$BASE/${ENV}.enc.json" ]]; then
    sops -d "$BASE/${ENV}.enc.json" >/dev/null \
      || fail "SOPS decrypt failed: $stack/$ENV"
  fi
done

echo "✔ Secrets OK"

############################################
# 5. YAML VALIDATION (GLOBAL)
############################################
echo "📄 Validating YAML..."

if command -v yq >/dev/null 2>&1; then
  mapfile -t yamls < <(find . -type f \( -name "*.yml" -o -name "*.yaml" \))

  for file in "${yamls[@]}"; do
    yq e '.' "$file" >/dev/null || fail "Invalid YAML: $file"
  done
else
  echo "⚠️ yq not installed, skipping YAML validation"
fi

echo "✔ YAML OK"

############################################
# 6. GITOPS VALIDATION
############################################
echo "🚀 Validating GitOps..."

./scripts/validate_gitops.sh || fail "GitOps validation failed"

echo "✔ GitOps OK"

############################################
# 7. SCRIPT VALIDATION
############################################
echo "🐚 Validating shell scripts..."

if command -v shellcheck >/dev/null 2>&1; then
  find scripts -type f -name "*.sh" -exec shellcheck {} \; \
    || fail "Shellcheck failed"
else
  echo "⚠️ shellcheck not installed, skipping"
fi

echo "✔ Scripts OK"

############################################
# 8. SANITY CHECKS (IMPORTANT)
############################################
echo "🧠 Running sanity checks..."

# ensure no .terraform dirs committed wrongly
if find . -type d -name ".terraform" | grep -q .; then
  echo "⚠️ Warning: .terraform directories detected"
fi

# ensure no plaintext secrets accidentally committed
if grep -r "aws_secret_access_key" . --exclude-dir=.git >/dev/null 2>&1; then
  echo "⚠️ Possible secret detected in repo"
fi

echo "✔ Sanity checks OK"

############################################
# DONE
############################################
echo "=============================="
echo "✅ ALL VALIDATIONS PASSED"
echo "=============================="
