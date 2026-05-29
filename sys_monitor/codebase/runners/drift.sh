#!/bin/bash
set -uo pipefail

# ============================================================
# DRIFT ENGINE v1
# ROLE: DECLARED INVENTORY vs REAL FILESYSTEM CONSISTENCY
# NO NETWORK | NO TF INIT | NO EXTERNAL STATE
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEBASE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${CODEBASE_ROOT}/../.." && pwd)"

EVIDENCE_DIR="${CODEBASE_ROOT}/evidence"
INVENTORY_FILE="${EVIDENCE_DIR}/inventory.json"
OUTPUT_FILE="${EVIDENCE_DIR}/drift.json"

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$EVIDENCE_DIR"

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
# LOAD INVENTORY SAFELY
# ------------------------------------------------------------

log "loading inventory from ${INVENTORY_FILE}"

if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo "[WARN] inventory missing"
    INVENTORY="{}"
else
    INVENTORY="$(cat "$INVENTORY_FILE" || echo '{}')"
fi

# ------------------------------------------------------------
# SAFE JSON EXTRACTOR
# ------------------------------------------------------------

safe_jq() {
    jq -r "$1" <<< "$INVENTORY" 2>/dev/null || true
}

# ------------------------------------------------------------
# PATH RESOLVER
# ------------------------------------------------------------

resolve() {
    local p="$1"
    [[ "$p" == /* ]] && echo "$p" || echo "${PROJECT_ROOT}/${p}"
}

# ------------------------------------------------------------
# ISSUE HANDLER
# ------------------------------------------------------------

add_issue() {
    local severity="$1"
    local type="$2"
    local file="$3"
    local message="$4"

    ISSUES+=("{\"severity\":\"$severity\",\"type\":\"$type\",\"file\":\"$file\",\"message\":\"$message\"}")

    ((ISSUES_FOUND++))

    if [[ "$severity" == "critical" ]]; then
        ((CRITICAL++))
    else
        ((WARNINGS++))
    fi
}

# ============================================================
# 1. FILE DRIFT CHECK
# ============================================================

log "checking declared file existence drift"

FILES=(
    $(safe_jq '
        .shell_scripts[],
        .workflows[],
        .yaml.kubernetes_manifests[],
        .yaml.helm_values[],
        .yaml.docker_compose[],
        .yaml.prometheus_configs[],
        .yaml.operational_configs[]
    ')
)

for f in "${FILES[@]:-}"; do
    [[ -z "$f" ]] && continue

    ((TOTAL_CHECKED++))

    path="$(resolve "$f")"

    if [[ ! -e "$path" ]]; then
        add_issue "critical" "missing_file" "$f" "declared file missing from filesystem"
    fi
done

# ============================================================
# 2. TERRAFORM DRIFT (DIR LEVEL ONLY)
# ============================================================

log "checking terraform directory drift"

TF_DIRS=($(safe_jq '.terraform.roots[]?'))

for d in "${TF_DIRS[@]:-}"; do
    [[ -z "$d" ]] && continue

    ((TOTAL_CHECKED++))

    path="$(resolve "$d")"

    if [[ ! -d "$path" ]]; then
        add_issue "critical" "missing_dir" "$d" "declared terraform root missing"
        continue
    fi

    # minimal sanity: must contain at least one .tf file
    if ! find "$path" -maxdepth 1 -name "*.tf" 2>/dev/null | grep -q .; then
        add_issue "warning" "empty_tf" "$d" "terraform root has no .tf files"
    fi
done

# ============================================================
# 3. MODULE DRIFT CHECK
# ============================================================

log "checking terraform module drift"

MODULES=($(safe_jq '.terraform.modules[]?'))

for m in "${MODULES[@]:-}"; do
    [[ -z "$m" ]] && continue

    ((TOTAL_CHECKED++))

    path="$(resolve "$m")"

    if [[ ! -d "$path" ]]; then
        add_issue "critical" "missing_module" "$m" "declared module missing"
    fi
done

# ============================================================
# 4. ORPHAN DETECTION (REAL FILES NOT IN INVENTORY)
# ============================================================

log "checking orphan files (light scan)"

# only scan known automation layers (bounded)
SCAN_DIRS=(
    "${PROJECT_ROOT}/scripts"
    "${PROJECT_ROOT}/sys_monitor"
)

for dir in "${SCAN_DIRS[@]}"; do
    [[ ! -d "$dir" ]] && continue

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        rel="${file#${PROJECT_ROOT}/}"

        ((TOTAL_CHECKED++))

        # check if file exists in inventory
        if ! grep -q "$rel" <<< "$INVENTORY"; then
            add_issue "warning" "orphan_file" "$rel" "file exists but not declared in inventory"
        fi
    done < <(find "$dir" -type f 2>/dev/null | head -n 300)
done

# ============================================================
# 5. SCORE
# ============================================================

SCORE=100
SCORE=$((SCORE - ISSUES_FOUND * 4))
(( SCORE < 0 )) && SCORE=0

# ============================================================
# OUTPUT
# ============================================================

ISSUES_JSON=$(printf "%s\n" "${ISSUES[@]}" | paste -sd ",")

cat > "$OUTPUT_FILE" <<EOF
{
  "engine": "drift",
  "scope": "inventory_vs_filesystem",
  "status": "completed",
  "timestamp": "${TIMESTAMP}",
  "summary": {
    "total_checked": ${TOTAL_CHECKED},
    "issues_found": ${ISSUES_FOUND},
    "critical": ${CRITICAL},
    "warnings": ${WARNINGS},
    "drift_score": ${SCORE}
  },
  "findings": [${ISSUES_JSON}]
}
EOF

log "drift evaluation completed"
log "issues=${ISSUES_FOUND}"
log "score=${SCORE}"
log "output=${OUTPUT_FILE}"

exit 0
