# Architecture: Terraform + ArgoCD Split Responsibility

## Overview

Portal Kombat uses a **hybrid approach** where Terraform and ArgoCD each manage distinct layers of the infrastructure platform.

## Responsibility Matrix

| Component | Managed By | Why |
|-----------|-----------|-----|
| **Crossplane Core** | Terraform | Better lifecycle management, dependencies |
| **UPJET Providers** | Terraform | Requires IRSA setup, complex dependencies |
| **Provider RBAC** | ArgoCD | Cluster-wide permissions, declarative |
| **XRDs** | ArgoCD | Platform API definitions, GitOps-friendly |
| **Compositions** | ArgoCD | Infrastructure templates, frequent updates |
| **ProviderConfigs** | ArgoCD | Environment-specific, GitOps-friendly |
| **Infrastructure Claims** | ArgoCD | Application-level resources, GitOps-native |

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         TERRAFORM LAYER                          │
│  (bootstrap/eks-bootstrap/)                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ✅ Crossplane Core (Helm chart)                                │
│  ✅ UPJET AWS Providers (19 families)                           │
│     - provider-upjet-aws-s3                                     │
│     - provider-upjet-aws-ec2                                    │
│     - provider-upjet-aws-iam                                    │
│     - provider-upjet-aws-rds                                    │
│     - ... (dynamodb, vpc, kms, lambda, sqs, sns, etc.)         │
│                                                                  │
│  ✅ IAM Roles + IRSA Configuration                              │
│     - crossplane-upbound-irsa role                              │
│     - Trust policy with OIDC                                    │
│                                                                  │
│  ✅ UPJET RuntimeConfig (with IRSA annotation)                  │
│  ✅ UPJET ProviderConfig (aws-provider-config)                  │
│  ✅ Kubernetes Provider + Helm Provider                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                          ARGOCD LAYER                            │
│  (environments/dev/argocd/)                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  📦 dev-rbac (Wave -2)                                          │
│     ✅ Provider RBAC ClusterRole                                │
│        - Aggregates into crossplane:allowed-provider-permissions│
│        - Grants ProviderConfig access                           │
│                                                                  │
│  📦 dev-platform-crossplane (Wave 0)                            │
│     ✅ XRDs (CompositeResourceDefinitions)                      │
│        - xobjectstorages.aws.plt.intelerad.io                   │
│     ✅ Compositions                                             │
│        - objectstorage-private                                  │
│     ✅ Functions                                                │
│        - function-patch-and-transform                           │
│     ❌ Providers (excluded via directory.exclude)               │
│                                                                  │
│  📦 dev-provider-configs (Wave 1)                               │
│     ✅ DeploymentRuntimeConfig (IRSA for future providers)      │
│     ✅ ProviderConfigs (environment-specific)                   │
│        - platform-dev (default)                                 │
│        - management-account (cross-account)                     │
│        - platform-prod                                          │
│                                                                  │
│  📦 dev-infrastructure (Wave 2)                                 │
│     ✅ Infrastructure Claims using XRDs                         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Sync Wave Order

```
Wave -2: RBAC (ClusterRoles for provider permissions)
    ↓
[Terraform-managed Crossplane + Providers already running]
    ↓
Wave  0: Platform (XRDs, Compositions, Functions)
    ↓
Wave  1: Provider Configs (IRSA configs, ProviderConfigs)
    ↓
Wave  2: Infrastructure (Buckets, VPCs, etc. using Claims)
```

---

## Key Design Decisions

### Why Terraform Manages Crossplane Core?

1. **Bootstrap Complexity**: Crossplane requires Helm installation, namespace creation, and CRD deployment
2. **Provider Dependencies**: UPJET providers need specific IRSA roles created before installation
3. **Stability**: Core infrastructure benefits from Terraform's explicit dependency management
4. **State Management**: Terraform state tracks Crossplane version, provider versions

### Why ArgoCD Manages Platform Abstractions?

1. **GitOps Native**: XRDs and Compositions change frequently, benefit from Git-based workflows
2. **Developer Self-Service**: Platform teams can update Compositions without Terraform access
3. **Environment Parity**: Same XRDs/Compositions across dev/staging/prod via ArgoCD sync
4. **Separation of Concerns**: Platform definitions separate from infrastructure installation

### Why Split Provider Configs?

- **Terraform**: Creates one default ProviderConfig (`aws-provider-config`) during bootstrap
- **ArgoCD**: Manages environment-specific and cross-account ProviderConfigs
- **Reason**: Different update frequencies - bootstrap configs rarely change, env configs change often

---

## File Structure

```
portal-kombat/
├── bootstrap/eks-bootstrap/
│   ├── main.tf                          # Terraform: Crossplane + UPJET providers
│   ├── crossplane-irsa.tf               # Terraform: IAM roles for IRSA
│   ├── providers/upjet-aws/*.yaml       # Terraform: UPJET provider templates
│   └── values/crossplane.yaml           # Terraform: Crossplane Helm values
│
├── environments/dev/argocd/
│   ├── root-app.yaml                    # ArgoCD: Root App-of-Apps
│   ├── rbac-app.yaml                    # ArgoCD: Provider RBAC (Wave -2)
│   ├── platform-apps.yaml               # ArgoCD: XRDs/Compositions (Wave 0)
│   ├── provider-configs-app.yaml        # ArgoCD: ProviderConfigs (Wave 1)
│   └── infrastructure-apps.yaml         # ArgoCD: Claims (Wave 2)
│
├── platform/
│   ├── xrds/                            # ArgoCD: Platform API definitions
│   ├── compositions/                    # ArgoCD: Infrastructure templates
│   ├── functions/                       # ArgoCD: Composition functions
│   └── providers/                       # ❌ DISABLED (Terraform manages)
│       └── README.md                    # Explains why empty
│
├── shared/configs/
│   ├── rbac/
│   │   └── crossplane-provider-rbac.yaml  # ArgoCD: Provider ClusterRole
│   └── provider-configs/
│       ├── platform-dev.yaml            # ArgoCD: Default ProviderConfig
│       ├── management.yaml              # ArgoCD: Cross-account config
│       └── aws-upbound-runtime-config.yaml  # ArgoCD: IRSA runtime config
│
└── docs/
    ├── ARCHITECTURE-TERRAFORM-ARGOCD-SPLIT.md  # This file
    └── CROSSPLANE-IRSA-SETUP.md                # IRSA setup guide
```

---

## Provider Types: UPJET vs Native

### Current Setup: UPJET Providers ✅

```yaml
# Deployed by Terraform
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-upjet-aws-s3
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-upjet-aws:v1.6.0
```

**Characteristics**:
- Terraform-based (uses TF AWS provider under the hood)
- Mature, stable, wide AWS coverage
- Shares single ProviderConfig: `aws.upbound.io/v1beta1`
- 19 family-specific providers (s3, ec2, iam, rds, dynamodb, etc.)

### Alternative: Native Providers ❌ (Not Used)

```yaml
# Would be deployed by ArgoCD (if we switched)
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws-s3
spec:
  package: xpkg.upbound.io/upbound/provider-aws-s3:v1.7.0
```

**Characteristics**:
- Go-based, native Kubernetes controllers
- Each family has own ProviderConfig CRD
- Faster reconciliation, smaller footprint
- Less mature than UPJET

**Why Not Used**: We're using UPJET providers deployed by Terraform. Mixing both would cause conflicts.

---

## RBAC Architecture

### The Problem

By default, Crossplane RBAC Manager creates provider ClusterRoles but doesn't grant ProviderConfig access to UPJET providers.

**Error**:
```
User "system:serviceaccount:crossplane-system:provider-upjet-aws-s3-*"
cannot list resource "providerconfigs" in API group "aws.upbound.io"
```

### The Solution

Create a ClusterRole with aggregation label that grants all UPJET providers access:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: crossplane:provider:aws-upbound-providerconfigs
  labels:
    rbac.crossplane.io/aggregate-to-allowed-provider-permissions: "true"
rules:
- apiGroups: [aws.upbound.io, s3.upbound.io, ...]
  resources: [providerconfigs, providerconfigs/status, ...]
  verbs: [get, list, watch, ...]
```

**How it works**:
1. ClusterRole has aggregation label
2. Crossplane RBAC Manager sees the label
3. Automatically aggregates into `crossplane:allowed-provider-permissions`
4. All provider service accounts inherit these permissions

**Deployed by**: ArgoCD via `dev-rbac` app (Wave -2, before providers start)

---

## IRSA Configuration

### IAM Role (Terraform)

```hcl
module "crossplane_upbound_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name_prefix = "${cluster_name}-crossplane"

  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "crossplane-system:provider-upjet-aws-*"
      ]
    }
  }

  role_policy_arns = {
    crossplane_policy = aws_iam_policy.crossplane_provider.arn
  }
}
```

**Output**: `arn:aws:iam::654654563406:role/raiden-control-plane-crossplane...`

### RuntimeConfig (ArgoCD)

```yaml
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: aws-upbound-runtime-config
spec:
  serviceAccountTemplate:
    metadata:
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::654654563406:role/..."
```

**How IRSA Works**:
1. Provider pod gets service account with IAM role annotation
2. EKS injects `AWS_WEB_IDENTITY_TOKEN_FILE` env var
3. AWS SDK uses token to assume IAM role via OIDC
4. Provider gets temporary AWS credentials (auto-rotated)
5. Provider can manage AWS resources

---

## Operational Workflows

### Updating Crossplane Version

```bash
# Update Terraform
cd bootstrap/eks-bootstrap
vim values/crossplane.yaml  # Change version

# Apply
terraform apply

# Verify
kubectl get pods -n crossplane-system
kubectl get providers
```

### Adding a New XRD

```bash
# Create XRD definition
vim platform/xrds/compute/xrd-ec2-instance.yaml

# Commit and push
git add platform/xrds/
git commit -m "Add EC2 instance XRD"
git push

# ArgoCD auto-syncs
kubectl get xrd xec2instances.aws.plt.intelerad.io
```

### Adding a New Environment-Specific ProviderConfig

```bash
# Create ProviderConfig
vim shared/configs/provider-configs/platform-staging.yaml

# Commit and push
git add shared/configs/provider-configs/
git commit -m "Add staging ProviderConfig"
git push

# ArgoCD auto-syncs
kubectl get providerconfig platform-staging
```

### Troubleshooting Provider RBAC

```bash
# Check if ClusterRole exists
kubectl get clusterrole crossplane:provider:aws-upbound-providerconfigs

# Check aggregation
kubectl get clusterrole crossplane:allowed-provider-permissions -o yaml

# Check provider service account
kubectl get sa -n crossplane-system provider-upjet-aws-s3-* -o yaml

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-s3
```

---

## Migration Path (If Moving to Full ArgoCD)

If you decide to move Crossplane installation to ArgoCD in the future:

1. **Uncomment** `environments/dev/argocd/crossplane-install.yaml`
2. **Update** `root-app.yaml` to include `crossplane-install.yaml`
3. **Remove** Crossplane from Terraform (`main.tf`)
4. **Choose** provider family (keep UPJET or switch to Native)
5. **Update** provider manifests in `platform/providers/`
6. **Re-enable** providers in `platform-apps.yaml` (remove exclude)
7. **Apply** Terraform changes
8. **Sync** ArgoCD root app

---

## Benefits of This Architecture

### ✅ Clear Separation of Concerns
- Infrastructure installation (Terraform) vs platform configuration (ArgoCD)
- Stable foundation vs dynamic abstractions

### ✅ Best Tool for Each Job
- Terraform: Complex dependencies, state management, AWS resource creation
- ArgoCD: GitOps, declarative sync, environment parity

### ✅ Reduced Blast Radius
- Platform team updates XRDs/Compositions without touching Crossplane core
- Terraform changes don't trigger unnecessary provider restarts

### ✅ Operational Flexibility
- Can update platform definitions independently
- Can roll back platform changes without affecting foundation

### ✅ Gradual Migration Path
- Can move more to ArgoCD incrementally
- Or keep hybrid approach indefinitely

---

## Related Documentation

- [IRSA Setup Guide](./CROSSPLANE-IRSA-SETUP.md) - Complete IRSA configuration
- [Quick Start](./QUICK-START.md) - Getting started guide
- [Architecture Overview](./ARCHITECTURE.md) - High-level architecture

---

## Summary

**Terraform**: Foundation (Crossplane + UPJET Providers + IRSA)
**ArgoCD**: Platform (XRDs + Compositions + ProviderConfigs + Claims)

This architecture provides stability for the infrastructure foundation while enabling GitOps-driven platform evolution.
