# ============================================================
# KubApp — GitOps Workflows Layer (ArgoCD + CI/CD Control Plane)
# ============================================================

# ------------------------------------------------------------
# OVERVIEW — WHAT THIS SYSTEM IS
# ------------------------------------------------------------
# The KubApp workflows layer is a GitOps control plane built on
# top of Kubernetes + Terraform where Git acts as the single
# source of truth for:

# - Infrastructure state (Terraform)
# - Application registry (JSON manifests)
# - Deployment state (Helm values + ingress definitions)
# - Runtime versioning (Docker images)
# - Cluster health validation (verification + drift detection)

# Every change flows through controlled GitHub Actions pipelines
# that validate, transform, and reconcile system state.


# ------------------------------------------------------------
# CORE PHILOSOPHY
# ------------------------------------------------------------

# 1. Git is the source of truth
# Every change ends in Git (infra, apps, runtime, state)

# 2. State is explicitly tracked
# gitops/state/current.json
# controls:
# - active environment
# - workflow correlation
# - validation context

# 3. Every mutation is reversible
# - snapshots (verify_runtime.yml)
# - tags (stable-*)
# - rollback workflows (rollback.yml)

# 4. Drift is expected, not ignored
# The system actively detects and reconciles:
# - Terraform drift (tf_drift.yml)
# - Ingress drift (validate_ingress.yml)
# - Runtime drift (verify_runtime.yml)

# 5. Safety gates are mandatory
# - manual approvals (production workflows)
# - strict vs repair modes
# - environment-based controls


# ------------------------------------------------------------
# WORKFLOW ARCHITECTURE
# ------------------------------------------------------------

# The system is organized into layered workflows:

# Layer 1 → Infrastructure (Terraform Core)
# Layer 2 → Cluster Bootstrap (ArgoCD setup)
# Layer 3 → Application Build Engine
# Layer 4 → GitOps Registry Engine
# Layer 5 → Application Provisioning Engine
# Layer 6 → Application Removal Engine
# Layer 7 → Ingress Reconciliation Engine
# Layer 8 → Runtime Verification Engine
# Layer 9 → Drift Detection Engine
# Layer 10 → State & Safety Control Layer


# ------------------------------------------------------------
# LAYER 1 — INFRASTRUCTURE (terraform.yml)
# ------------------------------------------------------------
# This is the infrastructure brain of the system.

# Responsibilities:
# - VPC, IAM, EKS provisioning
# - Kubernetes cluster bootstrap
# - OIDC AWS authentication
# - encrypted tfvars via SOPS
# - separation of infra and K8s stacks

# Flow:
# Plan → Approval (prod) → Apply → Bootstrap → Cleanup hooks

# Includes destroy pipeline:
# - extracts cluster metadata
# - cleans Kubernetes first
# - destroys EKS + infra
# - cleans logs and leftovers


# ------------------------------------------------------------
# LAYER 2 — CLUSTER BOOTSTRAP (setup_argocd.yml)
# ------------------------------------------------------------
# Converts raw EKS into GitOps-ready platform.

# Responsibilities:
# - configure kubeconfig
# - install SOPS + AGE keys
# - install ArgoCD GitHub App secret
# - install metrics-server
# - run bootstrap scripts

# Result:
# - ArgoCD connected to GitHub
# - cluster ready for reconciliation
# - ingress + DNS synchronization active


# ------------------------------------------------------------
# LAYER 3 — APPLICATION BUILD ENGINE (build.yml)
# ------------------------------------------------------------
# Core application factory pipeline.

# Responsibilities:
# - scan docker/ directories
# - build Docker images (cached or fresh)
# - push to registry
# - generate JSON manifests per service

# Runtime metadata stored:
# - image
# - tag
# - port
# - health endpoints
# - volumes
# - runtime flags

# Outputs:
# - registry artifacts
# - GitOps registry update commit


# ------------------------------------------------------------
# LAYER 4 — GITOPS REGISTRY ENGINE (update.yml)
# ------------------------------------------------------------
# Runtime update mechanism.

# Responsibilities:
# - reads gitops/state/current.json
# - resolves active services
# - updates Helm values:
#   - image
#   - tag
# - commits changes

# Purpose:
# Enables deployment updates without rebuilding images


# ------------------------------------------------------------
# LAYER 5 — APPLICATION PROVISIONING (add_new_app.yml)
# ------------------------------------------------------------
# Auto-onboarding system for new services.

# Responsibilities:
# - validate state file
# - read registry JSON artifacts
# - generate Helm values
# - inject secrets
# - register ingress routes
# - commit GitOps changes

# Result:
# New application automatically enters Kubernetes


# ------------------------------------------------------------
# LAYER 6 — APPLICATION REMOVAL (remove_app.yml)
# ------------------------------------------------------------
# Controlled deletion pipeline.

# Responsibilities:
# - executes cleanup scripts
# - removes Helm entries
# - updates GitOps state
# - commits removal

# Purpose:
# Ensures safe deletion (no manual kubectl usage)


# ------------------------------------------------------------
# LAYER 7 — INGRESS RECONCILIATION (validate_ingress.yml)
# ------------------------------------------------------------
# Self-healing ingress validation system.

# Responsibilities:
# - compare registry vs ingress state
# - detect drift:
#   - missing services
#   - invalid routes

# Modes:
# - strict → fail pipeline
# - repair → auto-fix
# - auto_register → inject missing services

# Purpose:
# Ensures routing always matches desired state


# ------------------------------------------------------------
# LAYER 8 — RUNTIME VERIFICATION (verify_runtime.yml)
# ------------------------------------------------------------
# Post-deployment validation engine.

# Responsibilities:
# - connect to EKS
# - validate cluster state
# - verify ArgoCD sync
# - generate deployment snapshot
# - tag stable commit

# Behavior:
# - can trigger rollback suggestion on failure


# ------------------------------------------------------------
# LAYER 9 — DRIFT DETECTION (tf_drift.yml)
# ------------------------------------------------------------
# Terraform state observability layer.

# Responsibilities:
# - terraform plan -detailed-exitcode
# - detect:
#   - no drift
#   - drift detected
#   - errors
# - aggregate per module

# Purpose:
# Infrastructure divergence visibility


# ------------------------------------------------------------
# LAYER 10 — STATE & SAFETY CONTROL
# ------------------------------------------------------------

# unlock.yml
# - forces terraform state unlock

# rollback.yml
# - GitOps rollback (target or full reset)

# stable_deploy.yml
# - resolves latest stable tag
# - restores snapshot state


# ------------------------------------------------------------
# DATA FLOW MODEL
# ------------------------------------------------------------

# Docker Build
#   ↓
# registry JSON artifact
#   ↓
# GitOps registry commit
#   ↓
# add_new_app.yml
#   ↓
# Helm value generation
#   ↓
# ingress registration
#   ↓
# ArgoCD sync
#   ↓
# verify_runtime.yml
#   ↓
# stable tag creation


# Parallel Systems:
# - tf_drift.yml → infrastructure health
# - validate_ingress.yml → routing correctness
# - update.yml → runtime image updates


# ------------------------------------------------------------
# KEY DESIGN DECISIONS
# ------------------------------------------------------------

# 1. State file as coordination layer
# gitops/state/current.json controls workflow context

# 2. GitHub App authentication everywhere
# avoids PAT leakage and improves security isolation

# 3. Artifact-based pipeline handoff
# build once → reuse across GitOps

# 4. Strict concurrency control
# prevents:
# - duplicate deployments
# - race conditions
# - conflicting ingress updates

# 5. Dual-mode execution
# - strict mode → fail fast
# - repair mode → auto-heal


# ------------------------------------------------------------
# SYSTEM SUMMARY
# ------------------------------------------------------------

# The KubApp workflows layer functions as a lightweight
# internal PaaS control plane built entirely on GitOps.

# It manages:
# - infrastructure provisioning
# - application lifecycle
# - image lifecycle
# - runtime reconciliation
# - drift detection
# - rollback + snapshot system
# - ingress self-healing
# - state coordination

# In essence:
#
# A fully Git-driven orchestration system that behaves like
# an internal platform engineering control plane.
# ============================================================
