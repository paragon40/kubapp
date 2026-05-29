#!/bin/bash
set -euo pipefail

# ============================================================
# KUBAPP — CODEBASE DISCOVERY ENGINE
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${CODEBASE_ROOT}/../.." && pwd)"

EVIDENCE_DIR="${CODEBASE_ROOT}/evidence"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${EVIDENCE_DIR}"

log() { echo "[INFO] $1"; }

log "starting discovery v2"

# ============================================================
# TERRAFORM ROOT STACKS
# ============================================================

mapfile -t TF_ROOTS < <(
    find "${PROJECT_ROOT}" -type f \
        \( -name "providers.tf" -o -name "versions.tf" -o -name "variables.tf" -o -name "main.tf" \) \
        ! -path "*/modules/*" \
        | sed "s|${PROJECT_ROOT}/||" \
        | xargs -r dirname \
        | sort -u
)

# ============================================================
# TERRAFORM MODULES
# ============================================================

mapfile -t TF_MODULES < <(
    find "${PROJECT_ROOT}/iac" -type f -name "*.tf" \
        | grep "/modules/" \
        | sed "s|${PROJECT_ROOT}/||" \
        | xargs -r dirname \
        | sort -u
)

# ============================================================
# SHELL SCRIPTS
# ============================================================

mapfile -t SHELL_SCRIPTS < <(
    find "${PROJECT_ROOT}" -type f -name "*.sh" \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# WORKFLOWS
# ============================================================

mapfile -t WORKFLOWS < <(
    find "${PROJECT_ROOT}/.github/workflows" -type f \
        \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null \
        | sed "s|${PROJECT_ROOT}/||" \
        | sort -u
)

# ============================================================
# YAML CLASSIFICATION (SEMANTIC)
# ============================================================

mapfile -t K8S_MANIFESTS < <(
    find "${PROJECT_ROOT}" -type f \( -name "*.yml" -o -name "*.yaml" \) \
        ! -path "*/.github/workflows/*" \
        ! -name "docker-compose*" \
        ! -name "values.yaml" \
        | while read f; do
            if grep -qE "apiVersion:|kind:|metadata:" "$f"; then
                echo "$f"
            fi
        done | sed "s|${PROJECT_ROOT}/||" | sort -u
)

mapfile -t DOCKER_COMPOSE < <(
    find "${PROJECT_ROOT}" -name "docker-compose*.yml" -o -name "docker-compose*.yaml" \
        | sed "s|${PROJECT_ROOT}/||" | sort -u
)

mapfile -t DOCKERFILES < <(
    find "${PROJECT_ROOT}" -name "Dockerfile" \
        | sed "s|${PROJECT_ROOT}/||" | sort -u
)

mapfile -t HELM_VALUES < <(
    find "${PROJECT_ROOT}" -name "values.yaml" \
        | sed "s|${PROJECT_ROOT}/||" | sort -u
)

mapfile -t PROMETHEUS < <(
    find "${PROJECT_ROOT}" -name "prometheus*.yml" -o -name "prometheus*.yaml" \
        | sed "s|${PROJECT_ROOT}/||" | sort -u
)

mapfile -t OPERATIONAL_CONFIGS < <(
    find "${PROJECT_ROOT}" -type f \( -name "*.yaml" -o -name "*.yml" \) \
        ! -path "*/.github/*" \
        ! -name "values.yaml" \
        ! -name "docker-compose*" \
        ! -name "prometheus*" \
        | sed "s|${PROJECT_ROOT}/||" | sort -u
)

# ============================================================
# JSON HELPER
# ============================================================

json_array() {
    local items=("$@")
    printf '['
    for i in "${!items[@]}"; do
        printf '"%s"' "${items[$i]}"
        [[ $i -lt $((${#items[@]} - 1)) ]] && printf ','
    done
    printf ']'
}

# ============================================================
# OUTPUT
# ============================================================

log "generating inventory"

cat > "${INVENTORY_FILE}" <<EOF
{
  "generated_at": "${TIMESTAMP}",
  "repository": "kubapp",

  "terraform": {
    "roots": $(json_array "${TF_ROOTS[@]}"),
    "modules": $(json_array "${TF_MODULES[@]}")
  },

  "shell_scripts": $(json_array "${SHELL_SCRIPTS[@]}"),

  "workflows": $(json_array "${WORKFLOWS[@]}"),

  "yaml": {
    "kubernetes_manifests": $(json_array "${K8S_MANIFESTS[@]}"),
    "helm_values": $(json_array "${HELM_VALUES[@]}"),
    "docker_files": $(json_array "${DOCKERFILES[@]}"),
    "docker_compose": $(json_array "${DOCKER_COMPOSE[@]}"),
    "prometheus_configs": $(json_array "${PROMETHEUS[@]}"),
    "operational_configs": $(json_array "${OPERATIONAL_CONFIGS[@]}")
  },

  "statistics": {
    "terraform_root_count": ${#TF_ROOTS[@]},
    "terraform_module_count": ${#TF_MODULES[@]},
    "shell_script_count": ${#SHELL_SCRIPTS[@]},
    "workflow_count": ${#WORKFLOWS[@]},
    "dockerfile_count": ${#DOCKERFILES[@]},
    "k8s_manifest_count": ${#K8S_MANIFESTS[@]}
  }
}
EOF

log "discovery workflow completed"
log "inventory written to ${INVENTORY_FILE}"
