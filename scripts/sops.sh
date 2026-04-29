#!/usr/bin/env bash
set -euo pipefail

: "${AGE_PUBLIC_KEY:?AGE_PUBLIC_KEY is not set}"

GITOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../gitops/secrets" && pwd)"

echo "🚀 Encrypting GitOps secrets in: $GITOPS_DIR"

shopt -s nullglob

for file in "$GITOPS_DIR"/*.{yaml,yml}; do
  [[ -f "$file" ]] || continue

  out="${file}.enc"

  echo "🔐 Encrypting $file → $out"

  sops --encrypt \
    --age "$AGE_PUBLIC_KEY" \
    "$file" > "$out"

  echo "✅ Done: $out"
done

echo "🎉 Local encryption complete"
