#
```
flowchart TD
    A[Developer] --> B[Git Push / Pull Request]

    B --> C[build.yml]

    C --> D[Discover Services]
    D --> E[Dynamic Build Matrix]
    E --> F[Build Docker Images]
    F --> G[Push Images to Docker Hub]
    G --> H[Generate Registry Metadata]

    H --> I[Commit GitOps Registry]
    I --> J[add_new_app.yml]

    J --> K[Validate Pipeline State]
    K --> L[Read Application Registry]

    L --> M[Generate values.yaml]
    L --> N[Generate SOPS Secrets]
    L --> O[Register Ingress]

    M --> P[GitOps Repository]
    N --> P
    O --> P

    P --> Q[ArgoCD]
    Q --> R[EKS / Kubernetes]

    R --> S[Runtime Verification]

