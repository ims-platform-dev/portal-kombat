# Portal Kombat - GitOps Repository Architecture

## Overview

This repository follows an **environment-first organization pattern** designed for managing AWS infrastructure using Crossplane via ArgoCD. The structure supports multi-environment, multi-region, and multi-account deployments while maintaining clarity and separation of concerns.

## Design Philosophy

1. **Environment-First**: All environment-specific resources live under `environments/{env}/`
2. **Platform Abstraction**: Infrastructure capabilities are defined once in `platform/`, used everywhere
3. **GitOps Native**: Designed for ArgoCD app-of-apps pattern with automated sync
4. **Scalability**: Easy to add new environments, regions, or accounts without refactoring

## Directory Structure

```
portal-kombat/
├── bootstrap/              # Bootstrap ArgoCD itself (initial setup only)
├── platform/               # Crossplane platform definitions (environment-agnostic)
├── environments/           # Environment-specific configurations
├── shared/                 # Shared resources across environments
└── docs/                   # Documentation
```

### Detailed Breakdown

#### `platform/` - Infrastructure Platform Layer

**Purpose**: Define infrastructure capabilities that can be consumed by any environment.

```
platform/
├── providers/              # Crossplane provider packages
│   └── aws-provider.yaml   # AWS provider installation
│
├── xrds/                   # CompositeResourceDefinitions (APIs)
│   ├── network/           # VPC, Subnets, etc.
│   ├── compute/           # EKS, EC2, etc.
│   ├── database/          # RDS, DynamoDB, etc.
│   └── storage/           # S3, EFS, etc.
│       └── xrd-s3-bucket.yaml
│
└── compositions/           # Composition implementations
    ├── network/
    ├── compute/
    ├── database/
    └── storage/
        └── s3-private.yaml  # Implementation: secure private S3 bucket
```

**Key Concepts**:
- **XRDs** (CompositeResourceDefinitions): Define the API users interact with
  - Example: "I want an S3 bucket with these parameters"
- **Compositions**: Implement the XRDs with actual AWS resources
  - Example: "Here's how to create a secure private S3 bucket"

#### `environments/{env}/` - Environment-Specific Resources

**Purpose**: Everything needed to run a specific environment (dev, staging, prod).

```
environments/dev/
├── argocd/                 # ArgoCD Applications for this environment
│   ├── root-app.yaml       # Entry point (App of Apps)
│   ├── platform-apps.yaml  # Deploy Crossplane, monitoring, etc.
│   ├── infrastructure-apps.yaml  # Deploy infrastructure claims
│   └── workload-apps.yaml  # Deploy application workloads
│
├── infrastructure/         # Infrastructure Claims (what to create)
│   ├── network/           # VPC, subnets for dev
│   ├── compute/           # EKS cluster for dev
│   ├── storage/           # S3 buckets for dev
│   └── database/          # RDS instances for dev
│
├── platform/               # Platform services for this environment
│   ├── monitoring/        # Prometheus, Grafana
│   └── ingress/           # Nginx ingress controller
│
└── workloads/              # Application deployments
    └── s3reader/          # Example application
```

**Key Concepts**:
- **Infrastructure Claims**: Use the platform APIs (XRDs) to request resources
  - Example: "Create me a VPC using the 'dev' composition"
- **Platform Services**: Kubernetes operators and tools (monitoring, ingress, etc.)
- **Workloads**: Your actual applications

#### `shared/` - Cross-Environment Resources

**Purpose**: Resources that are shared or need special handling across environments.

```
shared/
├── managed-resources/      # One-off resources not in compositions
│   ├── iam-roles/         # IAM roles and policies
│   └── route53-zones/     # DNS zones
│
└── configs/
    └── provider-configs/   # AWS credentials per account
        ├── dev-account.yaml
        ├── staging-account.yaml
        └── prod-account.yaml
```

## How It Works: The Flow

### 1. Define Platform Capabilities (One Time)

Create XRDs and Compositions in `platform/`:

```yaml
# platform/xrds/storage/xrd-s3-bucket.yaml
# Defines: "What parameters can users provide when creating an S3 bucket?"

# platform/compositions/storage/s3-private.yaml
# Implements: "How do we actually create a secure private S3 bucket?"
```

### 2. Claim Infrastructure (Per Environment)

Create claims in `environments/dev/infrastructure/`:

```yaml
# environments/dev/infrastructure/storage/app-bucket.yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage  # Using the XRD API
spec:
  parameters:
    bucketName: my-dev-app-bucket
    region: us-east-2
```

### 3. ArgoCD Deploys Everything

ArgoCD watches `environments/dev/argocd/` and deploys:
1. **Platform** (Crossplane providers, XRDs, Compositions)
2. **Infrastructure** (VPCs, EKS, S3 buckets)
3. **Platform Services** (Monitoring, ingress)
4. **Workloads** (Your applications)

## Adding a New Environment

To add `staging`:

1. Copy the directory structure:
   ```bash
   cp -r environments/dev environments/staging
   ```

2. Update configurations:
   - Change bucket names, cluster names (must be unique)
   - Update ArgoCD apps to point to `staging` paths
   - Select appropriate compositions (e.g., `eks-staging` instead of `eks-dev`)

3. Add staging provider config:
   ```bash
   cp shared/configs/provider-configs/dev-account.yaml \
      shared/configs/provider-configs/staging-account.yaml
   ```

4. Deploy:
   ```bash
   kubectl apply -f environments/staging/argocd/root-app.yaml
   ```

## Crossplane: Managed Resources vs Compositions

### When to Use Managed Resources

**Direct AWS Resources** - Use when:
- One-off resources (e.g., single IAM role)
- Non-standard configurations
- Quick prototyping

**Example**:
```yaml
# shared/managed-resources/iam-roles/crossplane-role.yaml
apiVersion: iam.aws.crossplane.io/v1beta1
kind: Role
metadata:
  name: crossplane-sa-role
spec:
  forProvider:
    # Direct AWS API parameters
```

### When to Use Compositions

**Reusable Patterns** - Use when:
- Multiple instances needed (e.g., S3 buckets for each app)
- Standard configurations (e.g., "production-ready EKS")
- Need to bundle multiple resources together
- Want to abstract cloud provider details

**Example**:
```yaml
# Claim (what users write)
kind: ObjectStorage
spec:
  parameters:
    bucketName: my-bucket

# Composition creates: Bucket + Lifecycle Policy + Encryption + Tags
```

## Multi-Region / Multi-Account Strategy

### Multi-Region (Future)

Option 1: Region as a parameter
```
environments/dev/infrastructure/compute/
├── eks-us-east-2.yaml
└── eks-us-west-2.yaml
```

Option 2: Region as a directory
```
environments/dev/
├── us-east-2/
│   └── infrastructure/
└── us-west-2/
    └── infrastructure/
```

### Multi-Account

Use separate provider configs:
```
shared/configs/provider-configs/
├── dev-account.yaml        # Account 111111111111
├── staging-account.yaml    # Account 222222222222
└── prod-account.yaml       # Account 333333333333
```

Reference in claims:
```yaml
spec:
  providerConfigRef:
    name: prod-account  # Use production AWS account
```

## ArgoCD App-of-Apps Pattern

### Hierarchy

```
root-app.yaml (Entry Point)
    ↓
    ├── platform-apps.yaml → Deploys Crossplane
    ├── infrastructure-apps.yaml → Deploys VPC, EKS, S3
    └── workload-apps.yaml → Deploys applications
```

### Sync Order

ArgoCD automatically handles dependencies:
1. Platform (Crossplane providers, XRDs, Compositions)
2. Provider Configs (AWS authentication)
3. Infrastructure (Claims create actual resources)
4. Platform Services (Monitoring, ingress)
5. Workloads (Applications)

### Deployment

**Initial Bootstrap**:
```bash
kubectl apply -f environments/dev/argocd/root-app.yaml
```

**Everything Else**: Automated by ArgoCD watching Git

## Best Practices

### 1. Keep Platform Layer Clean
- XRDs define simple, user-friendly APIs
- Compositions handle complexity internally
- No environment-specific logic in platform/

### 2. Use Descriptive Names
```
# Good
environments/dev/infrastructure/storage/user-uploads-bucket.yaml

# Bad
environments/dev/s3.yaml
```

### 3. Tag Everything
```yaml
tags:
  - key: Environment
    value: dev
  - key: ManagedBy
    value: Crossplane
  - key: Project
    value: portal-kombat
```

### 4. Document Compositions
Each composition should have comments explaining:
- What it creates
- When to use it vs alternatives
- Any dependencies or prerequisites

### 5. Test in Dev First
Always test changes in `environments/dev/` before promoting to staging/prod.

## Troubleshooting

### Check ArgoCD Sync Status
```bash
kubectl get applications -n argocd
```

### Check Crossplane Resources
```bash
# Check if XRDs are installed
kubectl get xrd

# Check if Compositions are available
kubectl get compositions

# Check if Claims are successful
kubectl get objectstorage
kubectl describe objectstorage my-app-data-bucket
```

### Check Provider Logs
```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

## References

- [Crossplane Documentation](https://docs.crossplane.io/)
- [ArgoCD Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [GitOps Principles](https://opengitops.dev/)
