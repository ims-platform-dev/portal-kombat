# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Portal Kombat is a GitOps-native infrastructure platform using **Crossplane** and **ArgoCD** to manage AWS infrastructure declaratively through Kubernetes. The repository follows an environment-first organization pattern.

## Key Architecture Concepts

### Three-Layer Structure

1. **Infrastructure Definitions Layer** (`infra-definitions/`): Environment-agnostic infrastructure capabilities
   - **XRDs** (CompositeResourceDefinitions): Define user-facing APIs for infrastructure
   - **Compositions**: Implement XRDs with actual AWS resources
   - **Providers**: Crossplane provider packages (AWS S3, EC2, EKS, IAM, RDS)

2. **Environment Layer** (`environments/{env}/`): Environment-specific configurations
   - `argocd/`: ArgoCD Applications using App-of-Apps pattern
   - `infrastructure/`: Claims that use platform XRDs to request resources
   - `cluster-addons/`: Environment-specific cluster services (cert-manager, external-dns, nginx-ingress, karpenter)
   - `workloads/`: Application deployments

3. **Shared Layer** (`shared/`): Cross-environment resources
   - `configs/provider-configs/`: AWS authentication per account (IRSA)
   - `managed-resources/`: One-off AWS resources (IAM roles, Route53 zones)

### GitOps Flow

```
Git Commit → ArgoCD Sync → Crossplane → AWS Resources
```

ArgoCD watches Git and automatically deploys changes. Crossplane reconciles Kubernetes resources into AWS infrastructure.

## Common Development Commands

### ArgoCD Operations

```bash
# Deploy root application (initial setup)
kubectl apply -f environments/dev/argocd/root-apps.yaml

# Check application sync status
kubectl get applications -n argocd

# Watch sync progress
kubectl get applications -n argocd -w

# Force sync an application
kubectl patch application dev-crossplane-platform -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Crossplane Operations

```bash
# Install Crossplane (initial setup)
kubectl apply -f bootstrap/crossplane/install.yaml
kubectl wait --for=condition=ready pod -l app=crossplane -n crossplane-system --timeout=300s

# Check provider health
kubectl get providers

# Check XRDs are installed
kubectl get xrd

# Check compositions are available
kubectl get compositions

# Check provider configs
kubectl get providerconfigs

# View all Crossplane-managed resources
kubectl get managed

# Check specific resource types
kubectl get objectstorage  # Custom XRD claims
kubectl get bucket  # AWS S3 buckets
```

### Resource Management

```bash
# Create infrastructure using platform API
kubectl apply -f environments/dev/infrastructure/storage/my-bucket.yaml

# Check claim status
kubectl describe objectstorage my-app-data-bucket

# Check events for troubleshooting
kubectl get events -n crossplane-system --sort-by='.lastTimestamp'

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=50
```

### Testing and Validation

```bash
# Validate YAML before applying
find environments/dev -name "*.yaml" -exec kubectl apply --dry-run=client -f {} \;

# Check for YAML syntax errors
find . -name "*.yaml" -exec yamllint {} \;
```

## Architecture Patterns

### Crossplane: Managed Resources vs Compositions

**Use Managed Resources when:**
- Creating one-off resources (single IAM role)
- Prototyping or non-standard configurations
- Direct control over AWS API parameters is needed

**Use Compositions when:**
- Multiple instances needed (S3 buckets for each app)
- Standard configurations required (production-ready EKS)
- Bundling multiple resources together
- Abstracting cloud provider details

### Creating Infrastructure

**Option 1: Using Compositions (Recommended)**
```yaml
# environments/dev/infrastructure/storage/my-bucket.yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage  # Uses XRD from platform/xrds/
metadata:
  name: my-app-bucket
spec:
  parameters:
    bucketName: portal-kombat-dev-my-app-12345
    region: us-east-2
    versioning: true
```

**Option 2: Using Managed Resources (Direct AWS)**
```yaml
# environments/dev/infrastructure/storage/direct-bucket.yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: my-direct-bucket
spec:
  forProvider:
    region: us-east-2
  providerConfigRef:
    name: default
```

### ArgoCD App-of-Apps Pattern

The repository uses a hierarchical application structure with standardized naming conventions:

```
root-apps.yaml (Entry Point)
  ├── crossplane-platform-apps.yaml → Deploys Crossplane XRDs, Compositions, Providers
  ├── infrastructure-claims-apps.yaml → Deploys infrastructure claims and provider configs
  ├── k8s-platform-services-apps.yaml → Deploys Kubernetes cluster services
  └── workloads-apps.yaml → Deploys application workloads
```

Sync order is automatically managed by ArgoCD based on dependencies.

### ArgoCD Application Organization

Portal Kombat uses a four-layer hierarchical app-of-apps pattern:

**Root Application**: `environments/dev/argocd/root-apps.yaml`
- Entry point that deploys all child app-of-apps applications
- Application name: `dev-root-apps`

**Layer 1: Crossplane Platform** (`crossplane-platform-apps.yaml`)
- Deploys XRDs, Compositions, and Functions from `/platform`
- Deploys additional Provider packages from `/platform/providers`
- Applications:
  - `dev-crossplane-platform` (sync-wave: 0) - XRDs and Compositions
  - `dev-crossplane-providers` (sync-wave: -1) - Provider packages

**Layer 2: Infrastructure** (`infrastructure-claims-apps.yaml`)
- Deploys infrastructure resource claims from `/environments/dev/infrastructure`
- Deploys provider authentication configs from `/shared/configs/provider-configs`
- Applications:
  - `dev-infrastructure-claims` - S3 buckets, RDS databases, VPCs, networking
  - `dev-provider-configs` - AWS authentication via IRSA

**Layer 3: Kubernetes Platform Services** (`k8s-platform-services-apps.yaml`)
- Deploys cluster add-ons: cert-manager, external-dns, nginx-ingress
- Applications:
  - `dev-k8s-ebs-csi-driver` (sync-wave: 5) - EBS CSI driver for persistent storage
  - `dev-k8s-cert-manager` (sync-wave: 10) - Certificate management
  - `dev-k8s-external-dns` (sync-wave: 20) - DNS automation
  - `dev-k8s-nginx-ingress` (sync-wave: 30) - Ingress controller
- Note: Cluster autoscaling is handled by cluster-autoscaler deployed via Terraform in `bootstrap/terraform/eks-bootstrap/main.tf`

**Layer 4: Workloads** (`workloads-apps.yaml`)
- Deploys applications from `/environments/dev/workloads`
- Applications: `dev-{app-name}` (e.g., `dev-s3reader`)

For detailed naming conventions and guidelines, see [docs/NAMING_CONVENTIONS.md](docs/NAMING_CONVENTIONS.md).

## Adding New Resources

### Adding a New Environment

```bash
# 1. Copy dev structure
cp -r environments/dev environments/staging

# 2. Update all references (bucket names must be globally unique)
find environments/staging -type f -name "*.yaml" -exec sed -i '' 's/dev/staging/g' {} +

# 3. Create staging provider config
cp shared/configs/provider-configs/dev-account.yaml \
   shared/configs/provider-configs/staging-account.yaml

# 4. Deploy
kubectl apply -f environments/staging/argocd/root-apps.yaml
```

### Adding a New XRD and Composition

1. Define API in `platform/xrds/{category}/xrd-{resource}.yaml`
2. Create composition in `platform/compositions/{category}/{composition}.yaml`
3. Create claim in `environments/dev/infrastructure/{category}/{claim}.yaml`
4. Commit and push - ArgoCD deploys automatically

## Troubleshooting

### Provider Not Healthy

```bash
# Check provider status
kubectl describe provider provider-aws-s3

# Check IAM permissions (common cause)
kubectl get sa -n crossplane-system
kubectl describe sa -n crossplane-system | grep Annotations

# Restart provider pod
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
```

**Common causes:**
- IAM permissions missing (check IRSA configuration)
- Provider image pull failure
- Invalid provider configuration

See `shared/managed-resources/iam-roles/iam-policies/SETUP-INSTRUCTIONS.md` for IAM setup.

### Infrastructure Resource Not Ready

```bash
# Check resource details
kubectl describe bucket my-bucket-name

# Check events
kubectl get events --field-selector involvedObject.name=my-bucket-name

# Check provider logs for AWS errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 | grep -i error

# Check resource status conditions
kubectl get bucket my-bucket-name -o jsonpath='{.status.conditions}'
```

### ArgoCD Application OutOfSync

```bash
# Check application status
kubectl get application dev-crossplane-platform -n argocd -o yaml

# Force sync
kubectl patch application dev-crossplane-platform -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

## Important Development Practices

### Naming Conventions

- Bucket names: `portal-kombat-{env}-{purpose}-{unique-id}`
- Resource names: Be descriptive (e.g., `user-uploads-bucket` not `s3.yaml`)
- Use consistent environment prefixes: `dev-`, `staging-`, `prod-`

### Tagging

Always tag AWS resources:
```yaml
tags:
  - key: Environment
    value: dev
  - key: ManagedBy
    value: Crossplane
  - key: Project
    value: portal-kombat
```

### Development Workflow

1. **Test in dev first**: Always create/test changes in `environments/dev/`
2. **Use GitOps**: Never create resources manually - commit to Git
3. **Watch sync status**: Monitor ArgoCD sync after pushing changes
4. **Verify in AWS**: Check AWS console to confirm resources created correctly
5. **Promote to staging/prod**: After dev testing, copy and adapt for other environments

### Security

- Authentication uses **IRSA** (IAM Roles for Service Accounts)
- Provider configs in `shared/configs/provider-configs/` configure AWS credentials
- IAM role: `crossplane-sa-role` needs appropriate permissions
- Never commit AWS credentials or secrets to Git

### RBAC Management

RBAC (Role-Based Access Control) is managed separately from the standard app-of-apps pattern for security best practices:

```bash
# Apply RBAC manually (security best practice)
kubectl apply -f environments/dev/argocd/rbac-app.yaml
```

**Rationale for Separate Management**:
- RBAC changes are security-critical and require explicit review
- Prevents accidental RBAC modifications through automated sync
- Allows cluster-wide RBAC policies to be audited independently
- RBAC applies across all environments, not environment-specific

RBAC changes should never be auto-synced and require manual approval for security compliance.

## Bootstrap Process

For initial cluster setup:

```bash
# 1. Install Crossplane
kubectl apply -f bootstrap/crossplane/install.yaml
kubectl wait --for=condition=ready pod -l app=crossplane -n crossplane-system --timeout=300s

# 2. Deploy root ArgoCD application
kubectl apply -f environments/dev/argocd/root-apps.yaml

# 3. Watch deployment
kubectl get applications -n argocd -w

# Expected output should show:
# dev-root-apps              Synced   Healthy
# dev-crossplane-providers   Synced   Healthy
# dev-crossplane-platform    Synced   Healthy
# dev-infrastructure-claims  Synced   Healthy
# dev-provider-configs       Synced   Healthy
# dev-k8s-cert-manager      Synced   Healthy
# dev-k8s-external-dns      Synced   Healthy
# dev-k8s-nginx-ingress     Synced   Healthy
# dev-k8s-karpenter         Synced   Healthy

# 4. Verify providers
kubectl get providers

# 5. Verify provider configs
kubectl get providerconfigs
```

See `bootstrap/crossplane/crossplane.sh` for detailed bootstrap script (reference only).

## Additional Documentation

- `docs/NAMING_CONVENTIONS.md`: ArgoCD application naming conventions and guidelines
- `docs/ARCHITECTURE.md`: Detailed architecture documentation
- `docs/QUICK-START.md`: Step-by-step quick start guide
- `shared/managed-resources/iam-roles/iam-policies/SETUP-INSTRUCTIONS.md`: IAM configuration
- `README.md`: Comprehensive project overview

## External Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [AWS Provider Documentation](https://marketplace.upbound.io/providers/upbound/provider-aws/)
- [GitOps Principles](https://opengitops.dev/)
