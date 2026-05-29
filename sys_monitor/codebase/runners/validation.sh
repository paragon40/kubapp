#!/bin/bash

# ============================================================
# KUBAPP — CODEBASE VALIDATION ENGINE
# ============================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"

MODULE_NAME="validation"
VALIDATION_FILE="$(evidence_file "validation")"

log_info "validation engine started"

# ============================================================
# STATE
# ============================================================

TOTAL_CHECKED=0
ISSUES=()

# ============================================================
# LOAD INVENTORY (SAFE)
# ============================================================

log_info "loading inventory from ${INVENTORY_FILE}"

if [[ ! -f "${INVENTORY_FILE}" ]]; then
    STATUS="fail"
    ERRORS+=("inventory file missing: ${INVENTORY_FILE}")
    INVENTORY="{}"
else
    INVENTORY="$(cat "${INVENTORY_FILE}")"
fi

# ============================================================
# ISSUE HANDLER
# ============================================================

add_issue() {
    local severity="$1"
    local type="$2"
    local file="$3"
    local message="$4"

    ISSUES+=(
        "$(jq -n \
            --arg severity "$severity" \
            --arg type "$type" \
            --arg file "$file" \
            --arg message "$message" \
            '{
                severity: $severity,
                type: $type,
                file: $file,
                message: $message
            }'
        )"
    )

    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    if [[ "$severity" == "critical" ]]; then
        STATUS="fail"
        ERRORS+=("${type}: ${file}")
    else
        WARNINGS+=("${type}: ${file}")
    fi
}

# ============================================================
# HELPERS
# ============================================================

exists_file() { [[ -f "$1" ]]; }
exists_dir() { [[ -d "$1" ]]; }

# ============================================================
# 1. TERRAFORM ROOTS
# ============================================================

log_info "validating terraform roots"

mapfile -t TF_ROOTS < <(echo "${INVENTORY}" | jq -r '.terraform.roots[]?')

for dir in "${TF_ROOTS[@]:-}"; do
    path="$(resolve_path "$dir")"

    if ! exists_dir "${path}"; then
        add_issue "critical" "missing_dir" "$dir" "terraform root missing"
    else
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    fi
done

# ============================================================
# 2. TERRAFORM MODULES
# ============================================================

log_info "validating terraform modules"

mapfile -t TF_MODULES < <(echo "${INVENTORY}" | jq -r '.terraform.modules[]?')

for dir in "${TF_MODULES[@]:-}"; do
    path="$(resolve_path "$dir")"

    if ! exists_dir "${path}"; then
        add_issue "critical" "missing_module" "$dir" "terraform module missing"
    else
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    fi
done

# ============================================================
# 3. SHELL SCRIPTS
# ============================================================

log_info "validating shell scripts"

mapfile -t SHELL_SCRIPTS < <(echo "${INVENTORY}" | jq -r '.shell_scripts[]?')

for file in "${SHELL_SCRIPTS[@]:-}"; do
    path="$(resolve_path "$file")"

    if ! exists_file "${path}"; then
        add_issue "warning" "missing_file" "$file" "shell script missing"
    else
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    fi
done

# ============================================================
# 4. WORKFLOWS
# ============================================================

log_info "validating workflows"

mapfile -t WORKFLOWS < <(echo "${INVENTORY}" | jq -r '.workflows[]?')

for file in "${WORKFLOWS[@]:-}"; do
    path="$(resolve_path "$file")"

    if ! exists_file "${path}"; then
        add_issue "critical" "missing_file" "$file" "workflow missing"
    else
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    fi
done

# ============================================================
# 5. REPO SECRETS (IMPORTANT FIX)
# ============================================================

log_info "validating repo secrets"

mapfile -t SECRETS < <(echo "${INVENTORY}" | jq -r '.repo_secrets[]?')

for file in "${SECRETS[@]:-}"; do
    path="$(resolve_path "$file")"

    if ! exists_file "${path}"; then
        add_issue "warning" "missing_secret" "$file" "secret file missing"
    else
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    fi
done

# ============================================================
# 6. YAML RESOURCES
# ============================================================

log_info "validating yaml resources"

mapfile -t YAML_FILES < <(
    echo "${INVENTORY}" | jq -r '
        .yaml.kubernetes_manifests[],
        .yaml.helm_values[],
        .yaml.docker_files[],
        .yaml.docker_compose[],
        .yaml.prometheus_configs[]
    ' 2>/dev/null
)

for file in "${YAML_FILES[@]:-}"; do
    path="$(resolve_path "$file")"

    if ! exists_file "${path}"; then
        add_issue "warning" "missing_file" "$file" "yaml resource missing"
    else
        TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    fi
done

CRITICAL_COUNT=0
WARNING_COUNT=0

for i in "${ISSUES[@]}"; do
    if echo "$i" | jq -e '.severity == "critical"' >/dev/null; then
        CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
    else
        WARNING_COUNT=$((WARNING_COUNT + 1))
    fi
done
# ============================================================
# OUTPUT
# ============================================================

log_info "writing validation evidence to ${VALIDATION_FILE}"

cat > "${VALIDATION_FILE}" <<EOF
{
  "module": "${MODULE_NAME}",
  "script": "${SCRIPT_NAME}",
  "timestamp": "${TIMESTAMP}",
  "status": "${STATUS}",

  "summary": {
    "total_checked": ${TOTAL_CHECKED},
    "issues_found": ${#ISSUES[@]},
    "errors": ${CRITICAL_COUNT},
    "warnings": ${WARNING_COUNT}
  },

  "errors": $(json_errors),
  "warnings": $(json_warnings),
  "findings": $(printf '%s\n' "${ISSUES[@]}" | jq -s .)
}
EOF

log_info "validation completed"
log_info "output written to ${VALIDATION_FILE}"
log_info "status=${STATUS}"
