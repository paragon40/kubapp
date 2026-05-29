#!/bin/bash
set -euo pipefail

# ============================================================
# SECURITY ENGINE v6 (NON-FAIL / DATA-FIRST)
# RULE: NEVER EXIT ON FAILURE — EVERYTHING IS A FINDING
# OUTPUT MUST ALWAYS BE GENERATED
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(git rev-parse --show-toplevel 2>/dev/null || echo "$SCRIPT_DIR/../../..")" && pwd)"
INVENTORY="$PROJECT_ROOT/sys_monitor/codebase/evidence/inventory.json"
OUT="$PROJECT_ROOT/sys_monitor/codebase/evidence/security.json"

mkdir -p "$(dirname "$OUT")"

log() { echo "[INFO] $1"; }

# ------------------------------------------------------------
# STATE
# ------------------------------------------------------------

ISSUES=()
ISSUES_FOUND=0
CRITICAL=0
WARNINGS=0
TOTAL=0

# ------------------------------------------------------------
# SAFE ISSUE ADDER
# ------------------------------------------------------------

add() {
  local severity="${1:-warning}"
  local type="${2:-unknown}"
  local file="${3:-unknown}"
  local message="${4:-no message}"

  ISSUES+=("{\"severity\":\"$severity\",\"type\":\"$type\",\"file\":\"$file\",\"message\":\"$message\"}")
  ((ISSUES_FOUND++))

  if [[ "$severity" == "critical" ]]; then
    ((CRITICAL++))
  else
    ((WARNINGS++))
  fi
}

# ------------------------------------------------------------
# SAFE INVENTORY LOADING (NO FAILS EVER)
# ------------------------------------------------------------

log "loading inventory: $INVENTORY"

INVENTORY_RAW="{}"

if [[ -f "$INVENTORY" ]]; then
  INVENTORY_RAW="$(cat "$INVENTORY" 2>/dev/null || echo '{}')"
else
  add warning inventory "inventory_missing" "inventory.json missing, using empty dataset"
fi

# validate JSON but NEVER fail
if ! echo "$INVENTORY_RAW" | jq empty >/dev/null 2>&1; then
  add warning inventory "invalid_json" "inventory.json corrupted, using empty dataset"
  INVENTORY_RAW="{}"
fi

# ------------------------------------------------------------
# SAFE EXTRACTOR
# ------------------------------------------------------------

get() {
  echo "$INVENTORY_RAW" | jq -r ".$1[]? // empty" 2>/dev/null || true
}

resolve() {
  [[ -z "${1:-}" ]] && echo "" && return
  [[ "$1" == /* ]] && echo "$1" || echo "$PROJECT_ROOT/$1"
}

# ------------------------------------------------------------
# LOAD DATA (ALWAYS SAFE)
# ------------------------------------------------------------

mapfile -t SCRIPTS < <(get "shell_scripts")
mapfile -t WORKFLOWS < <(get "workflows")
mapfile -t YAML < <(get "yaml.kubernetes_manifests")

log "loaded scripts=${#SCRIPTS[@]} workflows=${#WORKFLOWS[@]} yaml=${#YAML[@]}"

# ------------------------------------------------------------
# SAFE SCAN FUNCTION (CORE GUARANTEE)
# ------------------------------------------------------------

scan_file() {
  local f="${1:-}"

  [[ -z "$f" ]] && return

  local path
  path="$(resolve "$f")"

  if [[ ! -f "$path" ]]; then
    add warning missing_file "$f" "file not found on disk"
    return
  fi

  ((TOTAL++))

  # ---------------------------
  # HIGH CONFIDENCE SECRETS
  # ---------------------------

  if grep -q "AKIA[0-9A-Z]\{16\}" "$path" 2>/dev/null; then
    add critical aws_key "$f" "AWS access key detected"
  fi

  if grep -q "PRIVATE KEY" "$path" 2>/dev/null; then
    add critical private_key "$f" "private key material detected"
  fi

  if grep -Eq "(password|token|api_key|secret)[[:space:]]*=" "$path" 2>/dev/null; then
    add warning secret "$f" "possible credential assignment"
  fi

  # ---------------------------
  # RISKY PATTERNS
  # ---------------------------

  if grep -q "curl" "$path" 2>/dev/null && grep -q "| bash" "$path" 2>/dev/null; then
    add warning exec "$f" "curl piped to bash"
  fi

  if grep -q "wget" "$path" 2>/dev/null && grep -q "| bash" "$path" 2>/dev/null; then
    add warning exec "$f" "wget piped to bash"
  fi

  if grep -q "eval(" "$path" 2>/dev/null; then
    add warning exec "$f" "eval usage detected"
  fi
}

# ------------------------------------------------------------
# SAFE LOOP EXECUTION (NEVER BREAKS)
# ------------------------------------------------------------

log "scanning scripts"
for f in "${SCRIPTS[@]:-}"; do
  scan_file "$f"
done

log "scanning yaml"
for f in "${YAML[@]:-}"; do
  scan_file "$f"
done

log "scanning workflows"
for f in "${WORKFLOWS[@]:-}"; do
  scan_file "$f"
done

# ------------------------------------------------------------
# SCORE (ALWAYS COMPUTED)
# ------------------------------------------------------------

SCORE=$((100 - CRITICAL*10 - WARNINGS*2))
(( SCORE < 0 )) && SCORE=0

# ------------------------------------------------------------
# OUTPUT (NEVER FAIL)
# ------------------------------------------------------------

ISSUES_JSON=$(printf "%s\n" "${ISSUES[@]}" | paste -sd ",")

cat > "$OUT" 2>/dev/null <<EOF || {
  echo "[WARN] failed to write output file, printing instead"
  echo "$ISSUES_JSON"
  exit 0
}
{
  "engine": "security",
  "status": "completed",
  "summary": {
    "total_checked": $TOTAL,
    "issues_found": $ISSUES_FOUND,
    "critical": $CRITICAL,
    "warnings": $WARNINGS,
    "score": $SCORE
  },
  "findings": [${ISSUES_JSON}]
}
EOF

log "completed"
log "issues=$ISSUES_FOUND score=$SCORE"
log "output=$OUT"

exit 0
