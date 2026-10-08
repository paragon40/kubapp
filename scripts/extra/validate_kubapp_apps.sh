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

############################################
# HELPERS
############################################

fail() {
    echo
    echo "[ERROR] ❌ $1"
    echo "=================================================="
    exit 1
}

check_file() {
    [[ -f "$1" ]] || fail "Missing required file: $1"
}

############################################
# START
############################################

echo
echo "=================================================="
echo "[INFO] KUBAPP APPLICATION VALIDATION"
echo "[INFO] DIRECTORY: $DOCKER_DIR"
echo "=================================================="
echo

[[ -d "$DOCKER_DIR" ]] || fail "Missing docker directory: $DOCKER_DIR"

############################################
# DISCOVER APPLICATIONS
############################################

mapfile -t APPS < <(
    find "$DOCKER_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' |
        sort
)

if [[ ${#APPS[@]} -eq 0 ]]; then
    fail "No application directories found under docker/"
fi

echo "[INFO] Found ${#APPS[@]} application(s)"
echo

############################################
# VALIDATE EACH APPLICATION
############################################

for app in "${APPS[@]}"; do

    APP_DIR="$DOCKER_DIR/$app"

    echo "--------------------------------------------------"
    echo "[INFO] APPLICATION: $app"
    echo "--------------------------------------------------"

    ########################################
    # Dockerfile
    ########################################

    if [[ ! -f "$APP_DIR/Dockerfile" ]]; then
        fail "$app: Dockerfile is required"
    fi

    echo "[INFO] ✅ Dockerfile found"

    ########################################
    # CI FILE
    ########################################

    CI_FILE=""

    if [[ -f "$APP_DIR/ci.yml" ]]; then
        CI_FILE="$APP_DIR/ci.yml"
    elif [[ -f "$APP_DIR/ci.yaml" ]]; then
        CI_FILE="$APP_DIR/ci.yaml"
    else
        fail "$app: ci.yml or ci.yaml is required"
    fi

    echo "[INFO] ✅ CI file found: ${CI_FILE#$ROOT/}"

    ########################################
    # CI YAML SYNTAX
    ########################################

    yq e '.' "$CI_FILE" >/dev/null \
        || fail "$app: invalid YAML in ${CI_FILE#$ROOT/}"

    ########################################
    # CI STRUCTURE
    ########################################

    if ! yq e 'has("runtime")' "$CI_FILE" | grep -q '^true$'; then
        fail "$app: ci.yml must contain 'runtime'"
    fi

    if [[ "$(yq e '.runtime | type' "$CI_FILE")" != "!!str" ]]; then
        fail "$app: ci.yml 'runtime' must be a string"
    fi

    if ! yq e 'has("ci_commands")' "$CI_FILE" | grep -q '^true$'; then
        fail "$app: ci.yml must contain 'ci_commands'"
    fi

    if [[ "$(yq e '.ci_commands | type' "$CI_FILE")" != "!!map" ]]; then
        fail "$app: ci.yml 'ci_commands' must be a mapping"
    fi

    ########################################
    # OPTIONAL CI COMMANDS
    ########################################

    for command in lint security security_env test build; do
        if yq e "has(\"ci_commands\") and .ci_commands | has(\"$command\")" "$CI_FILE" |
            grep -q '^true$'; then

            TYPE="$(yq e ".ci_commands.$command | type" "$CI_FILE")"

            if [[ "$TYPE" != "!!seq" ]]; then
                fail "$app: ci_commands.$command must be a list"
            fi
        fi
    done

    ########################################
    # OPTIONAL KUBAPP FILE
    ########################################

    KUBAPP_FILE=""

    if [[ -f "$APP_DIR/kubapp.yml" ]]; then
        KUBAPP_FILE="$APP_DIR/kubapp.yml"
    elif [[ -f "$APP_DIR/kubapp.yaml" ]]; then
        KUBAPP_FILE="$APP_DIR/kubapp.yaml"
    fi

    if [[ -n "$KUBAPP_FILE" ]]; then
        yq e '.' "$KUBAPP_FILE" >/dev/null \
            || fail "$app: invalid YAML in ${KUBAPP_FILE#$ROOT/}"

        echo "[INFO] ✅ kubapp configuration found"
    else
        echo "[INFO] ℹ️  No kubapp.yml/yaml (optional)"
    fi

    ########################################
    # OPTIONAL SECRETS
    ########################################

    SECRET_FOUND="no"

    for secret_file in \
        "$APP_DIR/secrets.yml" \
        "$APP_DIR/secrets.yaml" \
        "$APP_DIR/secret.yml" \
        "$APP_DIR/secret.yaml" \
        "$APP_DIR/.env"; do

        if [[ -f "$secret_file" ]]; then
            SECRET_FOUND="yes"

            case "$secret_file" in
                *.yml|*.yaml)
                    yq e '.' "$secret_file" >/dev/null \
                        || fail "$app: invalid YAML in ${secret_file#$ROOT/}"
                    ;;
                *.env)
                    echo "[INFO] ℹ️  .env found (encryption validation deferred)"
                    ;;
            esac

            echo "[INFO] ✅ Optional secret file found: ${secret_file#$ROOT/}"
        fi
    done

    if [[ "$SECRET_FOUND" == "no" ]]; then
        echo "[INFO] ℹ️  No secret file (optional)"
    fi

    echo "[INFO] ✅ $app passed"
    echo
done

############################################
# COMPLETE
############################################

echo "=================================================="
echo "✅ KUBAPP APPLICATION VALIDATION PASSED"
echo "=================================================="
