#!/bin/bash
set -euo pipefail

# ============================================================
# KUBAPP — POLICY ENFORCEMENT ENGINE v2
# ROLE: BOUNDARY + COUPLING RULES ONLY
# NO SYNTAX | NO STRUCTURE | NO PARSING VALIDATION
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${CODEBASE_ROOT}/../.." && pwd)"

EVIDENCE_DIR="${CODEBASE_ROOT}/evidence"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"
OUTPUT_FILE="${EVIDENCE_DIR}/policy.json"

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

file_contains() {
    grep -q "$1" "$2" 2>/dev/null
}

# ============================================================
# 1. SCRIPT ↔ IAC COUPLING POLICY
# ============================================================

log "checking script-to-iac coupling policy"

mapfile -t SCRIPTS < <(echo "$INVENTORY" | jq -r '.shell_scripts[]?')

for f in "${SCRIPTS[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    path="$(resolve "$f")"

    [[ ! -f "$path" ]] && continue

    # forbidden patterns
    if file_contains "iac/" "$path"; then
        add_issue "warning" "policy_violation" "$f" "script references iac internals"
    fi

    if file_contains "terraform" "$path"; then
        add_issue "warning" "policy_violation" "$f" "script directly references terraform internals"
    fi
done

# ============================================================
# 2. GITOPS ISOLATION POLICY
# ============================================================

log "checking gitops isolation policy"

mapfile -t YAML < <(echo "$INVENTORY" | jq -r '.yaml.kubernetes_manifests[]?')

for f in "${YAML[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    path="$(resolve "$f")"

    [[ ! -f "$path" ]] && continue

    if file_contains "kubectl apply" "$path"; then
        add_issue "warning" "policy_violation" "$f" "gitops manifest contains imperative kubectl call"
    fi
done

# ============================================================
# 3. SAMPLE ISOLATION POLICY
# ============================================================

log "checking sample isolation policy"

mapfile -t SAMPLE < <(echo "$INVENTORY" | jq -r '.. | strings | select(test("^sample/"))')

for f in "${SAMPLE[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    path="$(resolve "$f")"

    [[ ! -f "$path" ]] && continue

    if file_contains "iac/" "$path" || file_contains "terraform" "$path"; then
        add_issue "warning" "policy_violation" "$f" "sample code depends on production layers"
    fi
done

# ============================================================
# 4. SYS_MONITOR BOUNDARY POLICY
# ============================================================

log "checking sys_monitor boundaries"

mapfile -t MON < <(echo "$INVENTORY" | jq -r '.shell_scripts[]? | select(test("sys_monitor"))')

for f in "${MON[@]}"; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))

    path="$(resolve "$f")"
    [[ ! -f "$path" ]] && continue

    if file_contains "../" "$path"; then
        add_issue "warning" "policy_violation" "$f" "sys_monitor script uses unsafe relative traversal"
    fi
done

# ============================================================
# 5. DUPLICATE SCRIPT NAME POLICY
# ============================================================

log "checking duplicate script names"

mapfile -t ALL_SCRIPTS < <(echo "$INVENTORY" | jq -r '.shell_scripts[]?' | awk -F/ '{print $NF}' | sort)

dup=$(echo "${ALL_SCRIPTS[@]}" | tr ' ' '\n' | sort | uniq -d || true)

for name in $dup; do
    TOTAL_CHECKED=$((TOTAL_CHECKED + 1))
    add_issue "warning" "policy_violation" "$name" "duplicate script name detected across repo"
done

# ============================================================
# OUTPUT
# ============================================================

log "generating policy report"

ISSUES_JSON=$(printf "%s\n" "${ISSUES[@]}" | paste -sd ",")

cat > "$OUTPUT_FILE" <<EOF
{
  "engine": "policy",
  "scope": "rule_enforcement_only",
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

log "policy evaluation completed"
log "total_checked=${TOTAL_CHECKED}"
log "issues_found=${ISSUES_FOUND}"
log "critical=${CRITICAL}"
log "warnings=${WARNINGS}"
log "output=${OUTPUT_FILE}"

exit 0
