#!/bin/bash
set -uo pipefail

# ============================================================
# ARCHITECTURE ENGINE v4 (STABLE)
# ROLE: SYSTEM DESIGN HEALTH ONLY
# GUARANTEE: NEVER SILENTLY CRASH
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${CODEBASE_ROOT}/../.." && pwd)"

EVIDENCE_DIR="${CODEBASE_ROOT}/evidence"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"
OUTPUT_FILE="${EVIDENCE_DIR}/architecture.json"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "${EVIDENCE_DIR}"

log() { echo "[INFO] $1"; }

TOTAL_CHECKED=0
ISSUES_FOUND=0
CRITICAL=0
WARNINGS=0
ISSUES=()

# ============================================================
# SAFE INVENTORY LOAD
# ============================================================

log "loading inventory from ${INVENTORY_FILE}"

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "[WARN] missing inventory"
    INVENTORY="{}"
else
    INVENTORY="$(cat "$INVENTORY_FILE" || echo '{}')"
fi

# ============================================================
# SAFE ADD ISSUE
# ============================================================

add_issue() {
    local severity="$1"
    local type="$2"
    local area="$3"
    local message="$4"

    ISSUES+=("{\"severity\":\"$severity\",\"type\":\"$type\",\"area\":\"$area\",\"message\":\"$message\"}")

    ISSUES_FOUND=$((ISSUES_FOUND + 1))

    if [[ "$severity" == "critical" ]]; then
        CRITICAL=$((CRITICAL + 1))
    else
        WARNINGS=$((WARNINGS + 1))
    fi
}

# ============================================================
# SAFE JQ EXTRACTOR (NO CRASH)
# ============================================================

safe_jq_array() {
    local query="$1"

    jq -r "$query" <<< "$INVENTORY" 2>/dev/null || true
}

# ============================================================
# LOAD LAYERS (SAFE)
# ============================================================

mapfile -t SCRIPTS < <(safe_jq_array '.shell_scripts[]?')
mapfile -t TF_ROOTS < <(safe_jq_array '.terraform.roots[]?')
mapfile -t WORKFLOWS < <(safe_jq_array '.workflows[]?')

# ============================================================
# RULE 1 — SAMPLE ISOLATION
# ============================================================

log "checking sample isolation"

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    ((TOTAL_CHECKED++))

    [[ "$f" == sample/* ]] && add_issue "warning" "isolation" "sample" "sample script leakage into automation layer"
done

# ============================================================
# RULE 2 — SYS_MONITOR BOUNDARY
# ============================================================

log "checking sys_monitor boundaries"

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    ((TOTAL_CHECKED++))

    [[ "$f" == sys_monitor/cloud/* ]] && add_issue "warning" "boundary" "sys_monitor" "cloud logic inside monitoring layer"
done

# ============================================================
# RULE 3 — DUPLICATION
# ============================================================

log "checking duplicate tool roles"

find_count=0
validate_count=0

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    ((TOTAL_CHECKED++))

    case "$f" in
        *find*.sh) ((find_count++)) ;;
        *validate*.sh) ((validate_count++)) ;;
    esac
done

[[ $find_count -gt 1 ]] && add_issue "warning" "duplication" "scripts" "multiple find tools detected"
[[ $validate_count -gt 1 ]] && add_issue "warning" "duplication" "scripts" "multiple validate tools detected"

# ============================================================
# RULE 4 — INFRA COUPLING
# ============================================================

log "checking infra coupling signals"

for f in "${SCRIPTS[@]:-}"; do
    [[ -z "$f" ]] && continue
    ((TOTAL_CHECKED++))

    [[ "$f" == *iac* ]] && add_issue "warning" "coupling" "scripts" "script tied to iac layer"
done

# ============================================================
# RULE 5 — WORKFLOW BALANCE
# ============================================================

log "checking workflow balance"

SCRIPT_COUNT=${#SCRIPTS[@]}
WORKFLOW_COUNT=${#WORKFLOWS[@]}

TOTAL_CHECKED=$((TOTAL_CHECKED + SCRIPT_COUNT + WORKFLOW_COUNT))

if (( WORKFLOW_COUNT > 0 && SCRIPT_COUNT > WORKFLOW_COUNT * 10 )); then
    add_issue "warning" "imbalance" "automation" "script layer dominates workflows"
fi

# ============================================================
# OUTPUT
# ============================================================

ISSUES_JSON=$(printf "%s\n" "${ISSUES[@]}" | paste -sd ",")

cat > "$OUTPUT_FILE" <<EOF
{
  "engine": "architecture",
  "scope": "system_design_health_v4",
  "status": "completed",
  "timestamp": "${TIMESTAMP}",
  "summary": {
    "total_checked": ${TOTAL_CHECKED},
    "issues_found": ${ISSUES_FOUND},
    "critical": ${CRITICAL},
    "warnings": ${WARNINGS},
    "architecture_score": $((100 - ISSUES_FOUND * 3))
  },
  "findings": [${ISSUES_JSON}]
}
EOF

log "architecture evaluation completed"
log "issues=${ISSUES_FOUND}"
log "output=${OUTPUT_FILE}"

exit 0
