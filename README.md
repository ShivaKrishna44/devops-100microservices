# DevOps 100 Microservices - Production Issues Lab

A production-grade microservices platform designed to practice troubleshooting real-world production issues.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AWS Cloud                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                     VPC (10.0.0.0/16)                      │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │  │ Public Sub  │  │ Public Sub  │  │ Public Sub  │       │  │
│  │  │   AZ-1a     │  │   AZ-1b     │  │   AZ-1c     │       │  │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │  │
│  │         │                 │                 │              │  │
│  │  ┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐       │  │
│  │  │ Private Sub │  │ Private Sub │  │ Private Sub │       │  │
│  │  │   AZ-1a     │  │   AZ-1b     │  │   AZ-1c     │       │  │
│  │  └──────┬──────┘  └──────┴──────┘  └──────┬──────┘       │  │
│  │         └──────────────┬───────────────────┘              │  │
│  │                        │                                   │  │
│  │              ┌─────────┴─────────┐                        │  │
│  │              │    EKS Cluster     │                        │  │
│  │              │  ┌─────────────┐   │                        │  │
│  │              │  │  Node Group  │   │                        │  │
│  │              │  │  (t3.medium) │   │                        │  │
│  │              │  └─────────────┘   │                        │  │
│  │              └────────────────────┘                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

Deployed Services:
├── api-gateway          (nginx ingress)
├── user-service         (Python/Flask)
├── order-service        (Python/Flask)
├── payment-service      (Python/Flask)
├── notification-service (Python/Flask)
├── inventory-service    (Python/Flask)
├── ArgoCD               (GitOps deployments)
├── Prometheus           (Metrics collection)
├── Grafana              (Dashboards & Alerts)
└── AlertManager         (Alert routing)
```

## Components

| Directory | Purpose |
|-----------|---------|
| `terraform/` | AWS infrastructure (VPC, EKS, IAM, ALB) |
| `apps/` | Microservice source code + Dockerfiles |
| `charts/` | Helm charts for microservices |
| `kubernetes/` | ArgoCD apps, monitoring, ingress configs |
| `.github/workflows/` | CI/CD pipelines (build, test, deploy) |
| `scripts/` | Bootstrap and utility scripts |
| `docs/` | Troubleshooting runbooks |

## Quick Start

```bash
# 1. Deploy infrastructure
cd terraform
terraform init && terraform apply

# 2. Configure kubectl
aws eks update-kubeconfig --name devops-100ms-cluster --region us-east-1

# 3. Install platform components
./scripts/01-install-ingress.sh
./scripts/02-install-argocd.sh
./scripts/03-install-monitoring.sh

# 4. Deploy applications via ArgoCD
kubectl apply -f kubernetes/argocd/apps/
```

## Production Issues to Practice

See [docs/PRODUCTION-ISSUES.md](docs/PRODUCTION-ISSUES.md) for guided troubleshooting scenarios.
