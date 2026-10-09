#!/usr/bin/env bash

############################################
# GIT DIAGNOSIS
# Purpose:
#   Interpret facts returned by git_functions2.sh.
############################################

_GIT_DIAGNOSIS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$_GIT_DIAGNOSIS_DIR/git_functions2.sh"
unset _GIT_DIAGNOSIS_DIR

diagnose_git_history() {
    local upstream
    local ahead
    local behind

    upstream="$(get_git_upstream)"
    ahead="$(get_git_ahead_count)"
    behind="$(get_git_behind_count)"

    if [[ "$upstream" == "none" ]]; then
        echo "No upstream tracking branch is configured."
        return 0
    fi

    if [[ "$ahead" == "unavailable" ||
          "$behind" == "unavailable" ]]; then
        echo "Unable to determine the history relationship."
        return 0
    fi

    if [[ "$ahead" -gt 0 && "$behind" -gt 0 ]]; then
        echo "Local and upstream histories have diverged."

    elif [[ "$ahead" -gt 0 ]]; then
        echo "Local history is ahead of upstream."

    elif [[ "$behind" -gt 0 ]]; then
        echo "Local history is behind upstream."

    else
        echo "Local and upstream histories are synchronized."
    fi
}
