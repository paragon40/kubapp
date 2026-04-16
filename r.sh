#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="gitops/envs"

echo "🚀 Migrating GitOps structure to envs/<env>/apps/<service>"

for ENV_PATH in "$BASE_DIR"/*; do
  ENV=$(basename "$ENV_PATH")

  echo ""
  echo "=============================="
  echo "Processing ENV: $ENV"
  echo "=============================="

  # Skip if not directory
  [ -d "$ENV_PATH" ] || continue

  for SERVICE_PATH in "$ENV_PATH"/*; do
    SERVICE=$(basename "$SERVICE_PATH")

    # Skip if already migrated format
    if [[ "$SERVICE" == "apps" ]]; then
      continue
    fi

    TARGET_DIR="gitops/envs/$ENV/apps/$SERVICE"

    echo "📦 Moving $SERVICE → $TARGET_DIR"

    # Create target structure
    mkdir -p "$TARGET_DIR"

    # If values.yaml exists directly
    if [ -f "$SERVICE_PATH/values.yaml" ]; then
      mv "$SERVICE_PATH/values.yaml" "$TARGET_DIR/values.yaml"
    fi

    # If directory has multiple files
    if [ -d "$SERVICE_PATH" ]; then
      for f in "$SERVICE_PATH"/*; do
        if [ -f "$f" ]; then
          mv "$f" "$TARGET_DIR/"
        fi
      done
    fi

    # Remove empty old dir
    rmdir "$SERVICE_PATH" 2>/dev/null || true
  done
done

echo ""
echo "✅ Migration complete"
