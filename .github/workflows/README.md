# KubApp CI/CD

KubApp uses GitHub Actions to automate the application lifecycle from
source changes through container image creation, GitOps registry
generation, Kubernetes provisioning, deployment, verification,
rollback, and cleanup.

## CI/CD Architecture

[diagram]

## Pipeline Stages

1. Build
2. Registry Generation
3. GitOps Provisioning
4. Deployment
5. Runtime Verification
6. Rollback
7. Cleanup

## Workflow Categories

| Category | Workflows |
|---|---|
| Pipeline orchestration | activate_pipeline.yml |
| Application build | build.yml |
| GitOps provisioning | add_new_app.yml |
| Deployment | setup_argocd.yml, verify_runtime.yml |
| Rollback | get_stable_deploy.yml, rollback.yml |
| Cleanup | clean_argocd.yml, remove_app.yml |
| Ingress management | remove_svc.yml |
| Operations | fixer.yml |
| Debugging/artifacts | app_artifacts.yml, docker-push.yml |

## Documentation

- Pipeline Architecture
- Build Pipeline
- GitOps Provisioning
- Deployment
- Rollback
- Cleanup and Reconciliation
- Operational Workflows

