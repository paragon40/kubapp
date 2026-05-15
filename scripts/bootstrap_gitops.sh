#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOG_FILE="/tmp/gitops-bootstrap.log"
: > "$LOG_FILE"

log() {
  echo -e "$1" | tee -a "$LOG_FILE"
}

apply_debug() {
  local file="$1"
  local ns="$2"

  log "\n========================================"
  log " APPLYING: $file"
  log " NAMESPACE: $ns"
  log "========================================"

  if [[ ! -f "$file" ]]; then
    log "❌ FILE NOT FOUND: $file"
    return 1
  fi

  log " DRY RUN PREVIEW:"
  kubectl apply -f "$file" --dry-run=client -o yaml | tee -a "$LOG_FILE"

  log "\n APPLYING LIVE:"
  kubectl apply -f "$file" -v=8 | tee -a "$LOG_FILE"

  log "\n POST-APPLY CHECK:"
  kubectl get all -n "$ns" | tee -a "$LOG_FILE"
}

log "========================================"
log "GitOps Bootstrap Starting..."
log "ROOT: $ROOT"
log "========================================"

# -----------------------------
# STEP 1: ARGOCD APPSET
# -----------------------------
apply_debug "$ROOT/gitops/argocd/appset.yaml" "argocd"

# -----------------------------
# STEP 2: INGRESS CONTROLLER
# -----------------------------
apply_debug "$ROOT/gitops/argocd/ingress.yaml" "argocd"

# -----------------------------
# STEP 3: VERIFY CLUSTER STATE
# -----------------------------
log "\n========================================"
log "FINAL CLUSTER VERIFICATION (dev)"
log "========================================"

kubectl get deployments -n dev -o wide | tee -a "$LOG_FILE"
kubectl get pods -n dev -o wide --show-labels | tee -a "$LOG_FILE"
kubectl get all -n dev | tee -a "$LOG_FILE"

# -----------------------------
# STEP 4: CRITICAL CHECK (your bug detector)
# -----------------------------
log "\n========================================"
log "CHECKING MISSING APPS"
log "========================================"

for app in weather urlshortener metrics; do
  if kubectl get deploy "$app" -n dev >/dev/null 2>&1; then
    log "✅ $app: DEPLOYED"
  else
    log "❌ $app: MISSING"
  fi
done

log "\n========================================"
log "✅ GitOps Bootstrap Complete"
log "LOG FILE: $LOG_FILE"
log "========================================"
