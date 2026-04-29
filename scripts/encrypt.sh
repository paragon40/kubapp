#!/usr/bin/env bash
set -euo pipefail

SECRET_DIR="gitops/secrets"
FILE="$SECRET_DIR/github-repo-secret.yaml"
OUT="$FILE.enc"

echo "🔐 Encrypting: $FILE"

# Safety check
if [[ ! -f "$FILE" ]]; then
  echo "❌ File not found: $FILE"
  exit 1
fi

# Optional: remove old encrypted file
rm -f "$OUT"

# Stable SOPS encryption (NO input/output flags)
sops -e --age "$AGE_PUBLIC_KEY" "$FILE" > "$OUT"

echo "✅ Encrypted output: $OUT"

# Verify file is valid SOPS
echo "🔎 Validating encryption..."
sops -d "$OUT" > /dev/null

echo "✅ Encryption + decryption test passed"
