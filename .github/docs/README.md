# Architecture

```
Developer
   │
   ▼
Git Push / PR
   │
   ▼
build.yml
   │
   ├── Discover services
   ├── Build images
   ├── Push images
   ├── Generate registry metadata
   └── Commit GitOps state
            │
            ▼
      GitOps Registry
            │
            ▼
      add_new_app.yml
            │
            ├── Validate state
            ├── Read registry
            ├── Generate values
            ├── Generate secrets
            └── Register ingress
                     │
                     ▼
                GitOps Repo
                     │
                     ▼
                  ArgoCD
                     │
                     ▼
                Kubernetes
                     │
                     ▼
              Runtime Verification
