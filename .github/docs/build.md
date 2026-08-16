# KubApp Build Pipeline

The KubApp build pipeline is responsible for discovering application
services, building their Docker images, pushing the images to Docker Hub,
and generating the application metadata consumed by the GitOps pipeline.

The workflow is:

- [`build.yml`](../workflows/build.yml)

---

## Purpose

The build pipeline converts application source code under `docker/` into:

1. Docker images stored in Docker Hub.
2. Registry metadata describing the built application.
3. GitHub Actions artifacts containing that metadata.
4. GitOps registry updates committed back to the repository.

The pipeline therefore acts as the bridge between **application source code**
and the **GitOps deployment system**.

---

## Build Flow

```text
Application Source
       │
       ▼
 docker/<service>/
       │
       ▼
Discover Services
       │
       ▼
Generate Matrix
       │
       ▼
Build Docker Images
       │
       ▼
Push Images
       │
       ▼
Generate Registry Metadata
       │
       ▼
Upload Artifacts
       │
       ▼
Rebuild GitOps Registry
       │
       ▼
Commit Registry + State
