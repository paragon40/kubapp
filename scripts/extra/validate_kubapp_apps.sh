#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$ROOT" ]]; then
    echo "[ERROR] Unable to determine project root."
    exit 1
fi

cd "$ROOT"

DOCKER_DIR="$ROOT/docker"

# HELPERS
fail() {
    echo
    echo "[ERROR] ❌ $1"
    echo "=================================================="
    exit 1
}

check_yaml() {
    local file="$1"
    local label="$2"

    yq e '.' "$file" >/dev/null \
        || fail "$label: invalid YAML in ${file#$ROOT/}"
}

is_nonempty() {
    local value="${1:-}"
    value="${value//[[:space:]]/}"
    [[ -n "$value" ]]
}

# PRECHECKS
command -v yq >/dev/null 2>&1 \
    || fail "yq is required but was not found."

[[ -d "$DOCKER_DIR" ]] \
    || fail "Missing docker directory: $DOCKER_DIR"

# START
echo
echo "=================================================="
echo "[INFO] KUBAPP APPLICATION VALIDATION"
echo "[INFO] DIRECTORY: $DOCKER_DIR"
echo "=================================================="
echo

############################################
# DISCOVER APPLICATIONS
############################################

mapfile -t APPS < <(
    find "$DOCKER_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '*_app' \
        -printf '%f\n' |
        sort
)

if [[ ${#APPS[@]} -eq 0 ]]; then
    fail "No KUBAPP applications found. Application directories must end in '_app'."
fi

echo "[INFO] Found ${#APPS[@]} application(s)"
echo "---------------------------------------"
for app in "${APPS[@]}"; do
   echo "[INFO] $app"
done
echo

############################################
# VALIDATE EACH APPLICATION
############################################

for app in "${APPS[@]}"; do

    APP_DIR="$DOCKER_DIR/$app"
    CI_FILE="$APP_DIR/ci.yml"

    echo "--------------------------------------------------"
    echo "[INFO] APPLICATION: $app"
    echo "--------------------------------------------------"

    ########################################
    # REQUIRED FILES
    ########################################

    [[ -f "$APP_DIR/Dockerfile" ]] \
        || fail "$app: Dockerfile is required"

    echo "[INFO] ✅ Dockerfile found"

    [[ -f "$CI_FILE" ]] \
        || fail "$app: ci.yml is required"

    echo "[INFO] ✅ ci.yml found"

    ########################################
    # CI YAML SYNTAX
    ########################################

    check_yaml "$CI_FILE" "$app"

    ########################################
    # RUNTIME
    ########################################

    RUNTIME_TYPE="$(yq e '.runtime | type' "$CI_FILE")"

    [[ "$RUNTIME_TYPE" == "!!str" ]] \
        || fail "$app: runtime must be a string"

    RUNTIME="$(yq e -r '.runtime' "$CI_FILE")"

    is_nonempty "$RUNTIME" \
        || fail "$app: runtime must not be empty"

    echo "[INFO] ✅ Runtime: $RUNTIME"

    ########################################
    # CI COMMANDS STRUCTURE
    ########################################

    CI_COMMANDS_TYPE="$(yq e '.ci_commands | type' "$CI_FILE")"

    [[ "$CI_COMMANDS_TYPE" == "!!map" ]] \
        || fail "$app: ci_commands must be a mapping"

    CI_COMMANDS_COUNT="$(yq e '.ci_commands | length' "$CI_FILE")"

    [[ "$CI_COMMANDS_COUNT" =~ ^[0-9]+$ ]] \
        || fail "$app: unable to determine ci_commands entries"

    (( CI_COMMANDS_COUNT > 0 )) \
        || fail "$app: ci_commands must contain at least one stage"

    echo "[INFO] ✅ CI commands mapping found"

    ########################################
    # VALIDATE DECLARED CI STAGES
    ########################################

    mapfile -t STAGES < <(
        yq e -r '.ci_commands | keys | .[]' "$CI_FILE"
    )

    for stage in "${STAGES[@]}"; do

        [[ -n "$stage" ]] \
            || fail "$app: ci_commands contains an empty stage name"

        ####################################
        # EACH STAGE MUST BE A LIST
        ####################################

        STAGE_TYPE="$(
            STAGE="$stage" \
                yq e '.ci_commands[strenv(STAGE)] | type' "$CI_FILE"
        )"

        [[ "$STAGE_TYPE" == "!!seq" ]] \
            || fail "$app: ci_commands.$stage must be a list"

        STAGE_COUNT="$(
            STAGE="$stage" \
                yq e '.ci_commands[strenv(STAGE)] | length' "$CI_FILE"
        )"

        [[ "$STAGE_COUNT" =~ ^[0-9]+$ ]] \
            || fail "$app: unable to validate ci_commands.$stage"

        ####################################
        # EMPTY STAGE POLICY
        ####################################

        # security_env may intentionally be empty.
        if [[ "$stage" == "security_env" && "$STAGE_COUNT" -eq 0 ]]; then
            echo "[INFO] ℹ️  ci_commands.security_env is empty (allowed)"
            continue
        fi

        (( STAGE_COUNT > 0 )) \
            || fail "$app: ci_commands.$stage must not be empty"

        ####################################
        # VALIDATE COMMAND ENTRIES
        ####################################

        for ((i = 0; i < STAGE_COUNT; i++)); do

            ITEM_TYPE="$(
                STAGE="$stage" INDEX="$i" \
                    yq e '.ci_commands[strenv(STAGE)][env(INDEX)] | type' "$CI_FILE"
            )"

            [[ "$ITEM_TYPE" == "!!str" ]] \
                || fail "$app: ci_commands.$stage entries must be strings"

            ITEM="$(
                STAGE="$stage" INDEX="$i" \
                    yq e -r '.ci_commands[strenv(STAGE)][env(INDEX)]' "$CI_FILE"
            )"

            is_nonempty "$ITEM" \
                || fail "$app: ci_commands.$stage contains an empty command entry"

        done

        echo "[INFO] ✅ CI stage validated: $stage"
    done

    ########################################
    # OPTIONAL KUBAPP CONFIGURATION
    ########################################

    KUBAPP_FILE=""

    if [[ -f "$APP_DIR/kubapp.yml" ]]; then
        KUBAPP_FILE="$APP_DIR/kubapp.yml"
    elif [[ -f "$APP_DIR/kubapp.yaml" ]]; then
        KUBAPP_FILE="$APP_DIR/kubapp.yaml"
    fi

    if [[ -n "$KUBAPP_FILE" ]]; then
        check_yaml "$KUBAPP_FILE" "$app"
        echo "[INFO] ✅ kubapp configuration found"
    else
        echo "[INFO] ℹ️  No kubapp configuration (optional)"
    fi

    ########################################
    # OPTIONAL SECRET FILES
    SECRET_FOUND="no"

    for secret_file in \
        "$APP_DIR/secrets.yml" \
        "$APP_DIR/secrets.yaml" \
        "$APP_DIR/secret.yml" \
        "$APP_DIR/secret.yaml" \
        "$APP_DIR/.env"; do

        [[ -f "$secret_file" ]] || continue

        SECRET_FOUND="yes"

        case "$secret_file" in
            *.yml|*.yaml)
                check_yaml "$secret_file" "$app"
                ;;
            *.env)
                echo "[INFO] ℹ️  .env found; encryption validation is handled separately"
                ;;
        esac

        echo "[INFO] ✅ Optional secret file found: ${secret_file#$ROOT/}"
    done

    if [[ "$SECRET_FOUND" == "no" ]]; then
        echo "[INFO] ℹ️  No secret file (optional)"
    fi

    echo "[INFO] ✅ $app passed"
    echo
done

echo "=================================================="
echo "✅ KUBAPP APPLICATION VALIDATION PASSED"
echo "==========================================================="
