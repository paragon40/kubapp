#!/bin/bash

# ============================================================
# KUBAPP — CODEBASE DISCOVERY ENGINE
# ============================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="Discovery"

INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"

log_info "starting discovery engine"

# ============================================================
# VALIDATION
# ============================================================

require_binary "jq"
require_binary "find"

# ============================================================
# STATE
# ============================================================

TF_ROOTS=()
TF_MODULES=()

SHELL_SCRIPTS=()
WORKFLOWS=()

K8S_MANIFESTS=()
DOCKER_COMPOSE=()
DOCKERFILES=()
HELM_VALUES=()
PROMETHEUS_CONFIGS=()
OPERATIONAL_CONFIGS=()

ARGOCD_CONFIGS=()
GITOPS_SECRETS=()

DOCUMENTATION=()

# ============================================================
# TERRAFORM ROOT STACKS
# ============================================================

if ! mapfile -t TF_ROOTS < <(
    find "${PROJECT_ROOT}" -type f -name "*.tf" \
        ! -path "*/modules/*" \
        -printf '%h\n' \
        | sort -u \
        | while read -r dir; do

            if [[ \
                -f "${dir}/providers.tf" || \
                -f "${dir}/provider.tf"  || \
                -f "${dir}/versions.tf"  || \
                -f "${dir}/version.tf"   || \
                -f "${dir}/backend.tf"
            ]]; then
                echo "${dir}"
            fi
        done \
        | sed "s|${PROJECT_ROOT}/||"
); then
    STATUS="fail"
    ERRORS+=("terraform root discovery failed")
fi

# ============================================================
# TERRAFORM MODULES
# ============================================================

if ! mapfile -t TF_MODULES < <(
    find "${PROJECT_ROOT}/iac" -type f -name "*.tf" 2>/dev/null \
        | grep "/modules/" \
        | sed "s|${PROJECT_ROOT}/||" \
        | xargs -r dirname \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("terraform module discovery failed")
fi

# ============================================================
# SHELL SCRIPTS
# ============================================================

if ! mapfile -t SHELL_SCRIPTS < <(
    find "${PROJECT_ROOT}" \
        "${EXCLUDE_ARGS[@]}" \
        -type f \
        -name "*.sh" \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("shell script discovery failed")
fi

# ============================================================
# GITHUB WORKFLOWS
# ============================================================

if ! mapfile -t WORKFLOWS < <(
    find "${PROJECT_ROOT}/.github/workflows" \
        -type f \
        \( -name "*.yml" -o -name "*.yaml" \) \
        2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("workflow discovery failed")
fi

# ============================================================
# KUBERNETES MANIFESTS
# ============================================================

if ! mapfile -t K8S_MANIFESTS < <(
    find "${PROJECT_ROOT}" \
        -type f \
        \( -name "*.yml" -o -name "*.yaml" \) \
        ! -path "*/.github/workflows/*" \
        ! -path "*/.git/*" \
        ! -path "*/.terraform/*" \
        ! -name "docker-compose*" \
        ! -name "*.bak" \
        ! -name "values.yaml" \
        | while read -r file; do

            if grep -q "^apiVersion:" "${file}" &&
               grep -q "^kind:" "${file}"; then
                echo "${file}"
            fi
        done \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("kubernetes manifest discovery failed")
fi

# ============================================================
# DOCKER COMPOSE
# ============================================================

if ! mapfile -t DOCKER_COMPOSE < <(
    find "${PROJECT_ROOT}" \
        \( -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \) \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("docker compose discovery failed")
fi

# ============================================================
# DOCKERFILES
# ============================================================

if ! mapfile -t DOCKERFILES < <(
    find "${PROJECT_ROOT}" \
        -name "Dockerfile" \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("dockerfile discovery failed")
fi

# ============================================================
# HELM VALUES
# ============================================================

if ! mapfile -t HELM_VALUES < <(
    find "${PROJECT_ROOT}" \
        -name "values.yaml" \
        ! -path "*/.github/workflows/*" \
        ! -path "*/.git/*" \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("helm values discovery failed")
fi

# ============================================================
# PROMETHEUS CONFIGS
# ============================================================

if ! mapfile -t PROMETHEUS_CONFIGS < <(
    find "${PROJECT_ROOT}" \
        \( -name "prometheus*.yml" -o -name "prometheus*.yaml" \) \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    ERRORS+=("prometheus config discovery failed")
fi

# ============================================================
# ARGOCD CONFIGS
# ============================================================

if ! mapfile -t ARGOCD_CONFIGS < <(
    find "${PROJECT_ROOT}/gitops/argocd" \
        -type f \
        \( -name "*.yaml" -o -name "*.yml" \) \
        2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    WARNINGS+=("argocd config discovery partially failed")
fi


if ! mapfile -t REPO_SECRETS < <(
    find "${PROJECT_ROOT}" \
        -type f \
        \( \
            -name "*.enc" \
            -o -path "*/gitops/secrets*" \
            -o -path "*/docker/*/secrets.yml*" \
        \) \
        2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    WARNINGS+=("other secrets discovery partially failed")
fi

# ============================================================
# DOCUMENTATION
# ============================================================

if ! mapfile -t DOCUMENTATION < <(
    find "${PROJECT_ROOT}/docs" \
        -type f \
        2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
); then
    STATUS="fail"
    WARNINGS+=("documentation discovery partially failed")
fi

# ============================================================
# OUTPUT
# ============================================================

log_info "writing inventory evidence"

TMP_FILE="$(mktemp)"

cat > "${TMP_FILE}" <<EOF
{
  "module": "${MODULE_NAME}",
  "script": "${SCRIPT_NAME}",
  "timestamp": "${TIMESTAMP}",
  "status": "${STATUS}",

  "errors": $(json_errors),
  "warnings": $(json_warnings),

  "repository": "kubapp",

  "terraform": {
    "roots": $(json_array "${TF_ROOTS[@]}"),
    "modules": $(json_array "${TF_MODULES[@]}")
  },

  "shell_scripts": $(json_array "${SHELL_SCRIPTS[@]}"),

  "workflows": $(json_array "${WORKFLOWS[@]}"),

  "repo_secrets": $(json_array "${REPO_SECRETS[@]}"),

  "gitops": {
    "argocd_configs": $(json_array "${ARGOCD_CONFIGS[@]}")
  },

  "yaml": {
    "kubernetes_manifests": $(json_array "${K8S_MANIFESTS[@]}"),
    "helm_values": $(json_array "${HELM_VALUES[@]}"),
    "docker_files": $(json_array "${DOCKERFILES[@]}"),
    "docker_compose": $(json_array "${DOCKER_COMPOSE[@]}"),
    "prometheus_configs": $(json_array "${PROMETHEUS_CONFIGS[@]}")
  },

  "documentation": $(json_array "${DOCUMENTATION[@]}"),

  "statistics": {
    "terraform_root_count": ${#TF_ROOTS[@]},
    "terraform_module_count": ${#TF_MODULES[@]},
    "shell_script_count": ${#SHELL_SCRIPTS[@]},
    "workflow_count": ${#WORKFLOWS[@]},
    "dockerfile_count": ${#DOCKERFILES[@]},
    "k8s_manifest_count": ${#K8S_MANIFESTS[@]},
    "argocd_config_count": ${#ARGOCD_CONFIGS[@]}
  }
}
EOF

mv "${TMP_FILE}" "${INVENTORY_FILE}"

log_info "discovery engine completed"
log_info "inventory evidence written to ${INVENTORY_FILE}"
