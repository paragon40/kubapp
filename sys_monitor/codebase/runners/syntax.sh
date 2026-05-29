#!/bin/bash
set -euo pipefail

# ============================================================
# KUBAPP — SYNTAX VALIDATION ENGINE (v2 STRICT)
# ROLE: PURE FILE PARSING ONLY (NO STRUCTURE / NO ARCHITECTURE)
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${CODEBASE_ROOT}/../.." && pwd)"

EVIDENCE_DIR="${CODEBASE_ROOT}/evidence"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"
OUTPUT_FILE="${EVIDENCE_DIR}/syntax.json"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${EVIDENCE_DIR}"

log() { echo "[INFO] $1"; }

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------

TOTAL_CHECKED=0
ISSUES_FOUND=0
CRITICAL=0
WARNINGS=0
ISSUES=()

# ------------------------------------------------------------
# LOAD INVENTORY
# ------------------------------------------------------------

log "loading inventory from ${INVENTORY_FILE}"

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "[WARN] inventory missing"
    INVENTORY="{}"
else
    INVENTORY="$(cat "$INVENTORY_FILE")"
fi

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

add_issue() {
    local severity="$1"
    local type="$2"
    local file="$3"
    local message="$4"

    ISSUES+=("{\"severity\":\"$severity\",\"type\":\"$type\",\"file\":\"$file\",\"message\":\"$message\"}")

    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    if [[ "$severity" == "critical" ]]; then
        CRITICAL=$((CRITICAL + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi
}

resolve() {
    local p="$1"
    [[ "$p" == /* ]] && echo "$p" || echo "${PROJECT_ROOT}/${p}"
}

file_exists() {
    [[ -f "$1" ]]
}

# ============================================================
# 1. YAML SYNTAX (STRICT SAFE PARSE)
# ============================================================

log "validating YAML syntax"

mapfile -t YAML_FILES < <(
    echo "$INVENTORY" | jq -r '
        .yaml.kubernetes_manifests[],
        .yaml.helm_values[],
        .yaml.docker_compose[],
        .yaml.prometheus_configs[],
        .yaml.operational_configs[]
    ' 2>/dev/null
)

for f in "${YAML_FILES[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    path="$(resolve "$f")"

    if ! file_exists "$path"; then
        continue
    fi

    if ! python3 -c "import yaml,sys; yaml.safe_load(open('$path'))" 2>/dev/null; then
        add_issue "warning" "yaml_syntax" "$f" "invalid YAML syntax"
    fi
done

# ============================================================
# 2. SHELL SCRIPT SYNTAX
# ============================================================

log "validating shell syntax"

mapfile -t SHELL_SCRIPTS < <(echo "$INVENTORY" | jq -r '.shell_scripts[]?')

for f in "${SHELL_SCRIPTS[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    path="$(resolve "$f")"

    if ! file_exists "$path"; then
        continue
    fi

    if ! bash -n "$path" 2>/dev/null; then
        add_issue "warning" "bash_syntax" "$f" "bash syntax error"
    fi
done

# ============================================================
# 3. TERRAFORM SYNTAX (NO INIT, NO VALIDATE, PURE PARSE ONLY)
# ============================================================

log "validating terraform syntax (parse-only)"

mapfile -t TF_ROOTS < <(echo "$INVENTORY" | jq -r '.terraform.roots[]?')

for dir in "${TF_ROOTS[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    path="$(resolve "$dir")"

    if [[ ! -d "$path" ]]; then
        continue
    fi

    # STRICT RULE:
    # Only check if .tf files are syntactically readable via terraform fmt check
    if command -v terraform >/dev/null 2>&1; then
        if ! terraform fmt -check -recursive "$path" >/dev/null 2>&1; then
            add_issue "warning" "terraform_format" "$dir" "terraform formatting issues detected"
        fi
    fi
done

# ============================================================
# 4. JSON SYNTAX (EXPLICIT FILE LIST ONLY)
# ============================================================

log "validating JSON syntax"

mapfile -t JSON_FILES < <(
    echo "$INVENTORY" | jq -r '
        .shell_scripts[],
        .workflows[]
    ' 2>/dev/null | grep '\.json$' || true
)

for f in "${JSON_FILES[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    path="$(resolve "$f")"

    if ! file_exists "$path"; then
        continue
    fi

    if ! python3 -m json.tool "$path" >/dev/null 2>&1; then
        add_issue "warning" "json_syntax" "$f" "invalid JSON syntax"
    fi
done

# ============================================================
# OUTPUT
# ============================================================

log "generating syntax report"

ISSUES_JSON=$(printf "%s\n" "${ISSUES[@]}" | paste -sd ",")

cat > "$OUTPUT_FILE" <<EOF
{
  "engine": "syntax",
  "scope": "file_parsing_only",
  "status": "completed",
  "timestamp": "${TIMESTAMP}",

  "summary": {
    "total_checked": ${TOTAL_CHECKED},
    "issues_found": ${ISSUES_FOUND},
    "critical": ${CRITICAL},
    "warnings": ${WARNINGS}
  },

  "findings": [${ISSUES_JSON}]
}
EOF

log "syntax validation completed"
log "total_checked=${TOTAL_CHECKED}"
log "issues_found=${ISSUES_FOUND}"
log "critical=${CRITICAL}"
log "warnings=${WARNINGS}"
log "output=${OUTPUT_FILE}"

exit 0
