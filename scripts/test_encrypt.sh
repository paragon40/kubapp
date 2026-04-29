#!/usr/bin/env bash
set -euo pipefail

FILE="gitops/secrets/github-repo-secret.yaml"
ENC="${FILE}.enc"

echo "🧪 Roundtrip test starting..."

echo "🔐 Encrypting..."
sops -e --age "$AGE_PUBLIC_KEY" "$FILE" > "$ENC"

echo "🔓 Decrypting..."
DECRYPTED=$(sops -d "$ENC")

echo "📦 Validating Kubernetes manifest..."
echo "$DECRYPTED" | kubectl apply --dry-run=client -f -

echo "🎉 ROUNDTRIP SUCCESS"
