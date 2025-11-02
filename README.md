# Portal Kombat

**Production-grade GitOps infrastructure platform using Crossplane and ArgoCD**

> Manage AWS infrastructure declaratively through Kubernetes, with everything synced from Git.

[![GitOps](https://img.shields.io/badge/GitOps-enabled-brightgreen)](https://opengitops.dev/)
[![Crossplane](https://img.shields.io/badge/Crossplane-v1.14+-blue)](https://crossplane.io/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.9+-blue)](https://argo-cd.readthedocs.io/)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Repository Structure](#repository-structure)
- [How It Works](#how-it-works)
- [Usage Guide](#usage-guide)
- [Verification & Troubleshooting](#verification--troubleshooting)
- [Advanced Topics](#advanced-topics)
- [Contributing](#contributing)

---

## Overview

Portal Kombat is a **GitOps-native infrastructure platform** that enables teams to:

- 🏗️ **Provision AWS infrastructure** declaratively using Crossplane
- 🔄 **Automate deployments** through ArgoCD's App of Apps pattern
- 🌍 **Manage multiple environments** (dev, staging, prod) from a single repository
- 🔒 **Maintain security** with IRSA (IAM Roles for Service Accounts)
- 📦 **Define platform abstractions** for consistent, reusable infrastructure

### Why Portal Kombat?

**Traditional Infrastructure**:
```
Code → Terraform → Manual Apply → AWS Resources
```

**Portal Kombat**:
```
Git Commit → ArgoCD Sync → Crossplane → AWS Resources
```

**Key Benefits**:
- ✅ Git as single source of truth
- ✅ Automated reconciliation (self-healing)
- ✅ Kubernetes-native infrastructure management
- ✅ Environment parity through composition
- ✅ Full audit trail in Git history

---

## Architecture

### The Stack

```
┌─────────────────────────────────────────────────────────────┐
│                         Git Repository                       │
│                      (portal-kombat)                         │
└────────────────────────────┬────────────────────────────────┘
                             │ watches
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                          ArgoCD                              │
│                    (Continuous Delivery)                     │
└────────────────────────────┬────────────────────────────────┘
                             │ deploys
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    Crossplane                         │  │
│  │              (Infrastructure Provisioner)             │  │
│  └─────────────────────────┬─────────────────────────────┘  │
│                            │ provisions                      │
│                            ▼                                 │
│         ┌──────────────────────────────────────┐            │
│         │       AWS Provider (via IRSA)        │            │
│         └──────────────────┬───────────────────┘            │
└────────────────────────────┼──────────────────────────────┘
                             │ creates
                             ▼
                    ┌────────────────────┐
                    │    AWS Resources   │
                    │  (S3, EKS, RDS)    │
                    └────────────────────┘
```

### Design Philosophy

1. **Environment-First**: All environment-specific resources live under `environments/{env}/`
2. **Platform Abstraction**: Infrastructure capabilities defined once in `platform/`, used everywhere
3. **GitOps Native**: Every change flows through Git → ArgoCD → Kubernetes
4. **Declarative Everything**: Desired state in Git, reconciled continuously

---

## Quick Start

### Prerequisites

Before you begin, ensure you have:

- ✅ **EKS Cluster** (1.28+) with kubectl access
- ✅ **ArgoCD** installed on the cluster
- ✅ **AWS IAM** configured with IRSA for Crossplane
- ✅ **Git access** to this repository

### Initial Setup

#### Step 1: Bootstrap Crossplane (One-Time)

```bash
# Install Crossplane into the cluster
kubectl apply -f bootstrap/crossplane/install.yaml

# Wait for Crossplane to be ready
kubectl wait --for=condition=ready pod -l app=crossplane -n crossplane-system --timeout=300s

# Verify installation
kubectl get pods -n crossplane-system
```

#### Step 2: Deploy Root Application

```bash
# Apply the root ArgoCD application
kubectl apply -f environments/dev/argocd/root-app.yaml

# Watch ArgoCD sync everything
kubectl get applications -n argocd -w
```

#### Step 3: Verify Deployment

```bash
# Check all applications are synced
kubectl get applications -n argocd

# Check Crossplane providers are healthy
kubectl get providers

# Check provider configs
kubectl get providerconfigs
```

**Expected Output**:
```
NAME                    HEALTHY   REVISION   AGE
provider-aws-s3         True      1          5m
provider-aws-ec2        True      1          5m
provider-aws-eks        True      1          5m
provider-aws-iam        True      1          5m
provider-aws-rds        True      1          5m
```

---

## Repository Structure

```
portal-kombat/
├── platform/                    # Platform layer (environment-agnostic)
│   ├── providers/              # Crossplane provider installations
│   │   └── aws-provider.yaml   # AWS provider packages (s3, ec2, eks, iam, rds)
│   ├── xrds/                   # Custom resource definitions (APIs)
│   │   ├── storage/            # S3, EFS XRDs
│   │   ├── network/            # VPC, Subnet XRDs
│   │   ├── compute/            # EKS, EC2 XRDs
│   │   └── database/           # RDS, DynamoDB XRDs
│   └── compositions/           # Implementation of XRDs
│       ├── storage/            # How to create S3 buckets
│       ├── network/            # How to create VPCs
│       ├── compute/            # How to create EKS clusters
│       └── database/           # How to create RDS instances
│
├── environments/               # Environment-specific configurations
│   └── dev/                   # Development environment
│       ├── argocd/            # ArgoCD Applications
│       │   ├── root-app.yaml           # Entry point (App of Apps)
│       │   ├── platform-apps.yaml      # Deploys Crossplane
│       │   ├── infrastructure-apps.yaml # Deploys infra claims
│       │   └── workload-apps.yaml      # Deploys applications
│       ├── infrastructure/    # Infrastructure claims
│       │   ├── network/       # Dev VPCs, subnets
│       │   ├── compute/       # Dev EKS clusters
│       │   ├── storage/       # Dev S3 buckets
│       │   └── database/      # Dev RDS instances
│       ├── platform/          # Platform services for dev
│       │   ├── monitoring/    # Prometheus, Grafana
│       │   └── ingress/       # Ingress controllers
│       └── workloads/         # Application workloads
│           └── s3reader/      # Example application
│
├── shared/                    # Cross-environment resources
│   ├── configs/
│   │   └── provider-configs/  # AWS authentication per account
│   │       └── dev-account.yaml
│   └── managed-resources/     # Shared AWS resources
│       ├── iam-roles/         # IAM roles and policies
│       └── route53-zones/     # DNS zones
│
├── workloads/                 # Application deployments
│   ├── monitoring/            # Monitoring stack
│   └── s3reader/              # Example app
│
├── apps/                      # Application templates
│   └── templates/             # Reusable app templates
│
├── bootstrap/                 # Bootstrap scripts (initial setup)
│   ├── crossplane/
│   │   ├── install.yaml       # Crossplane installation manifest
│   │   ├── argocd.sh          # ArgoCD setup script
│   │   └── crossplane.sh      # Crossplane setup script
│   └── s3-state/              # Terraform state backend
│
├── examples/                  # Learning examples
│   └── crossplane/            # Example Crossplane resources
│       ├── README.md
│       ├── WALKTHROUGH.md
│       ├── 01-s3-bucket.yaml
│       ├── 03-eks-cluster-simple.yaml
│       └── 04-eks-cluster-custom.yaml
│
└── docs/                      # Documentation
    ├── ARCHITECTURE.md        # Detailed architecture docs
    ├── QUICK-START.md         # Step-by-step setup guide
    └── SETUP_SUMMARY.md       # Setup reference
```

---

## How It Works

### The GitOps Flow

```
1. Developer commits to Git
   ↓
2. ArgoCD detects change
   ↓
3. ArgoCD syncs to Kubernetes
   ↓
4. Crossplane detects new/changed resources
   ↓
5. Crossplane provisions AWS infrastructure
   ↓
6. Resources ready, status updated in Kubernetes
```

### ArgoCD App of Apps Pattern

```
root-app.yaml (Entry Point)
    ├── platform-apps.yaml → Deploys Crossplane + Providers
    │   └── platform/ directory
    │       ├── providers/
    │       ├── xrds/
    │       └── compositions/
    │
    ├── infrastructure-apps.yaml → Deploys Infrastructure Claims
    │   ├── environments/dev/infrastructure/
    │   └── shared/configs/provider-configs/
    │
    └── workload-apps.yaml → Deploys Applications
        └── environments/dev/workloads/
```

### Crossplane Composition Pattern

**Step 1: Define an API (XRD)**
```yaml
# platform/xrds/storage/xrd-s3-bucket.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: objectstorages.aws.platform.example
spec:
  group: aws.platform.example
  names:
    kind: ObjectStorage
  versions:
    - name: v1alpha1
      schema:
        openAPIV3Schema:
          properties:
            spec:
              parameters:
                bucketName: string
                region: string
                versioning: boolean
```

**Step 2: Implement the API (Composition)**
```yaml
# platform/compositions/storage/s3-private.yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: objectstorage.aws.platform.example
spec:
  resources:
    - name: bucket
      base:
        apiVersion: s3.aws.crossplane.io/v1beta1
        kind: Bucket
    - name: encryption
      base:
        apiVersion: s3.aws.crossplane.io/v1beta1
        kind: BucketServerSideEncryptionConfiguration
    - name: versioning
      base:
        apiVersion: s3.aws.crossplane.io/v1beta1
        kind: BucketVersioning
```

**Step 3: Use the API (Claim)**
```yaml
# environments/dev/infrastructure/storage/my-bucket.yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage
metadata:
  name: my-app-data-bucket
spec:
  parameters:
    bucketName: portal-kombat-dev-app-data
    region: us-east-2
    versioning: true
```

---

## Usage Guide

### Creating Infrastructure

#### Option 1: Using Compositions (Recommended)

Create a claim using your platform API:

```yaml
# environments/dev/infrastructure/storage/user-uploads.yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage
metadata:
  name: user-uploads-bucket
spec:
  parameters:
    bucketName: portal-kombat-dev-user-uploads
    region: us-east-2
    versioning: true
    environment: dev
```

**Commit and push**:
```bash
git add environments/dev/infrastructure/storage/user-uploads.yaml
git commit -m "Add user uploads bucket for dev"
git push
```

ArgoCD will automatically sync and Crossplane will provision the bucket.

#### Option 2: Using Managed Resources (Direct AWS)

For one-off resources or special cases:

```yaml
# environments/dev/infrastructure/storage/special-bucket.yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: portal-kombat-special-bucket
spec:
  forProvider:
    region: us-east-2
    acl: private
    locationConstraint: us-east-2
  providerConfigRef:
    name: default
```

### Deploying Applications

#### Step 1: Add Application Manifests

```bash
mkdir -p environments/dev/workloads/my-app
```

```yaml
# environments/dev/workloads/my-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:v1.0.0
        ports:
        - containerPort: 8080
```

#### Step 2: Register with ArgoCD

```yaml
# environments/dev/argocd/workload-apps.yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:your-org/portal-kombat.git
    targetRevision: main
    path: environments/dev/workloads/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### Step 3: Commit and Deploy

```bash
git add environments/dev/workloads/my-app/
git add environments/dev/argocd/workload-apps.yaml
git commit -m "Add my-app to dev environment"
git push
```

### Adding a New Environment

To add staging or production:

```bash
# 1. Copy dev structure
cp -r environments/dev environments/staging

# 2. Update all references
find environments/staging -type f -name "*.yaml" -exec sed -i '' 's/dev/staging/g' {} +

# 3. Update resource names to be unique
# Edit environments/staging/infrastructure/* to use unique names
# Example: portal-kombat-staging-* instead of portal-kombat-dev-*

# 4. Create staging provider config
cp shared/configs/provider-configs/dev-account.yaml \
   shared/configs/provider-configs/staging-account.yaml

# 5. Update ArgoCD root app
cp environments/dev/argocd/root-app.yaml \
   environments/staging/argocd/root-app.yaml
# Edit to point to environments/staging/argocd/

# 6. Deploy
kubectl apply -f environments/staging/argocd/root-app.yaml
```

---

## Verification & Troubleshooting

### Health Checks

#### 1. Check ArgoCD Applications

```bash
# All applications
kubectl get applications -n argocd

# Specific application details
kubectl get application dev-platform-crossplane -n argocd -o yaml

# Watch sync progress
watch kubectl get applications -n argocd
```

**Expected healthy state**:
```
NAME                        SYNC STATUS   HEALTH STATUS
dev-root                    Synced        Healthy
dev-platform-crossplane     Synced        Healthy
dev-infrastructure          Synced        Healthy
dev-provider-configs        Synced        Healthy
```

#### 2. Check Crossplane Providers

```bash
# Check provider health
kubectl get providers

# Check provider details
kubectl describe provider provider-aws-s3

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=50
```

#### 3. Check Infrastructure Resources

```bash
# Check XRDs
kubectl get xrd

# Check compositions
kubectl get compositions

# Check claims (if you have ObjectStorage claims)
kubectl get objectstorage

# Check managed resources (actual AWS resources)
kubectl get bucket
kubectl get bucketversioning
kubectl get bucketserversideencryptionconfiguration
```

#### 4. Check Resource Status

```bash
# Get detailed status of a resource
kubectl describe bucket portal-kombat-dev-example

# Check events
kubectl get events -n crossplane-system --sort-by='.lastTimestamp'
```

### Common Issues & Solutions

#### Issue: Provider Not Healthy

**Symptoms**: `kubectl get providers` shows `HEALTHY: False`

**Debug**:
```bash
kubectl describe provider provider-aws-s3
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

**Common Causes**:
- ❌ IAM permissions missing (check IRSA configuration)
- ❌ Provider image pull failure
- ❌ Invalid provider configuration

**Solution**:
```bash
# Check IRSA setup
kubectl get sa -n crossplane-system
kubectl describe sa -n crossplane-system | grep Annotations

# Restart provider pod
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

#### Issue: ArgoCD Application OutOfSync

**Symptoms**: Application shows `OutOfSync` status

**Debug**:
```bash
kubectl get application dev-platform-crossplane -n argocd -o yaml
kubectl describe application dev-platform-crossplane -n argocd
```

**Solution**:
```bash
# Manual sync
kubectl patch application dev-platform-crossplane -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Or use ArgoCD CLI
argocd app sync dev-platform-crossplane
```

#### Issue: Infrastructure Resource Not Ready

**Symptoms**: `kubectl get bucket` shows `READY: False`

**Debug**:
```bash
kubectl describe bucket my-bucket-name
kubectl get events --field-selector involvedObject.name=my-bucket-name
```

**Common Causes**:
- ❌ AWS API errors (permissions, quotas)
- ❌ Invalid configuration
- ❌ Provider not healthy

**Solution**:
```bash
# Check provider logs for AWS errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 | grep -i error

# Check resource status
kubectl get bucket my-bucket-name -o jsonpath='{.status.conditions}'
```

#### Issue: Crossplane Not Installing

**Symptoms**: `kubectl get pods -n crossplane-system` shows no pods

**Solution**:
```bash
# Check if namespace exists
kubectl get namespace crossplane-system

# Reinstall Crossplane
kubectl apply -f bootstrap/crossplane/install.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=crossplane -n crossplane-system --timeout=300s
```

### Useful Commands

```bash
# Get all Crossplane resources
kubectl api-resources | grep crossplane

# Get all resources managed by Crossplane
kubectl get managed

# Check Crossplane version
kubectl get deployment crossplane -n crossplane-system -o jsonpath='{.spec.template.spec.containers[0].image}'

# Force ArgoCD sync
argocd app sync dev-platform-crossplane --force

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

---

## Advanced Topics

### Multi-Region Deployments

**Option 1: Region as Parameter**
```yaml
environments/dev/infrastructure/storage/
├── us-east-2-bucket.yaml  # region: us-east-2
└── us-west-2-bucket.yaml  # region: us-west-2
```

**Option 2: Region as Directory**
```yaml
environments/dev/
├── us-east-2/
│   └── infrastructure/
└── us-west-2/
    └── infrastructure/
```

### Multi-Account Deployments

Create separate provider configs per account:

```yaml
# shared/configs/provider-configs/dev-account.yaml
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: dev-account
spec:
  credentials:
    source: IRSA

# shared/configs/provider-configs/prod-account.yaml
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: prod-account
spec:
  credentials:
    source: IRSA  # Different IRSA role ARN
```

Reference in claims:
```yaml
spec:
  providerConfigRef:
    name: prod-account
```

### Creating Custom XRDs

See `examples/crossplane/` for walkthroughs on creating:
- Custom S3 bucket compositions
- EKS cluster compositions
- VPC compositions
- RDS database compositions

### CI/CD Integration

```yaml
# .github/workflows/deploy.yaml
name: Deploy Infrastructure
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Validate YAML
        run: |
          find . -name "*.yaml" -exec yamllint {} \;
      - name: Dry-run with kubectl
        run: |
          kubectl apply --dry-run=client -f environments/dev/
```

---

## Contributing

### Development Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/add-rds-composition
   ```

2. **Make changes in `environments/dev/` first**
   ```bash
   # Test in dev before promoting
   vim environments/dev/infrastructure/database/my-rds.yaml
   ```

3. **Commit and push**
   ```bash
   git add .
   git commit -m "Add RDS instance for dev environment"
   git push origin feature/add-rds-composition
   ```

4. **Create Pull Request**
   - Ensure all checks pass
   - Get approval from platform team
   - Merge to main

5. **Promote to staging/prod**
   ```bash
   cp environments/dev/infrastructure/database/my-rds.yaml \
      environments/staging/infrastructure/database/
   # Update names and config for staging
   ```

### Coding Standards

- ✅ Use descriptive resource names
- ✅ Add labels for environment, team, cost-center
- ✅ Document complex compositions with comments
- ✅ Test in dev before promoting to prod
- ✅ Use compositions for reusable patterns
- ✅ Use managed resources for one-off resources

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] New infrastructure resource
- [ ] Composition/XRD
- [ ] Configuration change
- [ ] Bug fix
- [ ] Documentation

## Testing
- [ ] Tested in dev environment
- [ ] ArgoCD sync successful
- [ ] Resources provisioned successfully
- [ ] No drift detected

## Checklist
- [ ] YAML validated
- [ ] Resources use proper naming convention
- [ ] Labels applied
- [ ] Documentation updated
```

---

## Project Status

**Current State**: ✅ Development environment operational

**Recent Updates**:
- 🧹 Repository cleanup completed (2025-11-01)
- ✅ Migrated to environment-first structure
- ✅ Platform abstraction layer implemented
- ✅ GitOps with ArgoCD fully configured

**Next Steps**:
- [ ] Add staging environment
- [ ] Add production environment
- [ ] Create VPC composition
- [ ] Create EKS composition
- [ ] Create RDS composition
- [ ] Add Kustomize overlays for environment variations
- [ ] Implement automated testing pipeline
- [ ] Add Prometheus monitoring for Crossplane

---

## Resources

### Documentation
- 📖 [Architecture Deep Dive](docs/ARCHITECTURE.md)
- 🚀 [Quick Start Guide](docs/QUICK-START.md)
- 🔐 [IAM Setup Instructions](shared/managed-resources/iam-roles/SETUP-INSTRUCTIONS.md)
- 📚 [Examples](examples/crossplane/)

### External Resources
- [Crossplane Documentation](https://docs.crossplane.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [AWS Provider Documentation](https://marketplace.upbound.io/providers/upbound/provider-aws/)
- [GitOps Principles](https://opengitops.dev/)

### Community
- [Crossplane Slack](https://slack.crossplane.io/)
- [ArgoCD Slack](https://argoproj.github.io/community/join-slack/)

---

## License

This project is proprietary and confidential.

---

## Maintainers

- Platform Team: platform-team@example.com
- Security: security@example.com

---

**Last Updated**: 2025-11-01
**Version**: 1.0.0
