#!/bin/bash

set -uo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/runtime.sh"
source "${CODEBASE_ROOT}/lib/json.sh"
require_binary "jq"
evid_dir="${EVIDENCE_DIR}"
inv_file="$evid_dir/inventory.json"

if [ ! -f "$inv_file" ]; then
  echo "Inventory File is NOT available, exiting..."
  exit 1
fi

function check() {
  local all=$@

  for each in "$all"; do
    if [[ -z "$each" ]]; then
      echo "one or both supplied Variables is empty"
      return 1
    fi
  done
  return 0
}

function extract() {
  local key=$1
  local file=$2

  res=$(check "$key" "$file")
  if [[ "$res" == 1 ]]; then
    exit
  fi

  value=$(jq -r "$key" "$file" )
  if [[ "$value" == "null" ]]; then
    echo "Value for $key is None"
  fi
  echo "Value: $value"
}

start() {
  local key=$1
  local file=$2
  res=$(check "$file")
  if [[ "$res" == 1 ]]; then
    exit 1
  fi
  first_ten=$(extract "$key" "$file" | head )
  echo "$first_ten"
}

echo "Starting..."
start ".files.all_files[]" "$inv_file"
echo "Done!"
