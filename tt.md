# kubapp

## Project Goals

Kubapp aims to provide a simplified but production-oriented Kubernetes platform on AWS.

Each section of the project has its own README file, so this is the outline.
For configuring and initializing KubApp, see [SETUP.md](https://github.com/codest40/kubapp_internal_platform/blob/main/SETUP.md).

## The project was built to:

* Automate Kubernetes infrastructure provisioning and management
* Provide an integrated CI/CD pipeline for building, validating, packaging, and deploying applications
* Simplify application delivery and cloud-native operations without overengineering the architecture
* Enable reproducible infrastructure and application deployments through Infrastructure as Code and GitOps workflows
* Improve operational visibility with integrated monitoring and observability
* Provide a maintainable file-based platform that is easy to operate, debug, and extend

## The project focuses on:

* Infrastructure as Code
* Application CI/CD and deployment automation
* GitOps workflows
* Kubernetes workload management
* Observability
* Secure cross-account access
* Automated infrastructure provisioning
* Operational simplicity

## Deployment Flow

KubApp includes a CI/CD deployment stage that connects application source code to the Kubernetes runtime.

The deployment flow is responsible for:

* Validating application changes
* Building application artifacts and container images
* Running application and configuration checks
* Packaging applications for deployment
* Publishing deployable artifacts
* Updating the Kubernetes deployment configuration
* Promoting workloads through the deployment workflow
* Managing the resulting Kubernetes workloads through GitOps

This gives KubApp an end-to-end flow:

**Infrastructure → CI/CD → Deployment → Kubernetes Runtime → Observability → Recovery**

## Extra Documentation

* [Architecture](https://github.com/codest40/kubapp_internal_platform/blob/main/docs/architecture.md)
* [Operations](https://github.com/codest40/kubapp_internal_platform/blob/main/docs/execution_flow.md)
* [Security](https://github.com/codest40/kubapp_internal_platform/blob/main/docs/security.md)
* [Observability](https://github.com/codest40/kubapp_internal_platform/blob/main/docs/observability.md)
* [Information](https://github.com/codest40/kubapp_internal_platform/blob/main/docs/extra_info.md)
