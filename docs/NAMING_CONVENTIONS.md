# ArgoCD Application Naming Conventions

## Overview

This document defines the standardized naming conventions for ArgoCD applications and app-of-apps files in the Portal Kombat GitOps repository. These conventions create self-documenting, intuitive resource names that clearly indicate scope, layer, and purpose.

## Quick Reference Guide

### Decision Matrix: Adding New Resources

When adding a new resource to the repository, use this decision matrix to determine the correct location:

```
┌─ Crossplane XRD/Composition? → Add to platform/
│  └─ Reference in: crossplane-platform-apps.yaml
│
├─ Crossplane Provider package? → Add to platform/providers/
│  └─ Reference in: crossplane-platform-apps.yaml (dev-crossplane-providers app)
│
├─ K8s cluster add-on (cert-manager, ingress, DNS, autoscaling)? → Add to environments/{env}/platform/
│  └─ Reference in: k8s-platform-services-apps.yaml
│
├─ Infrastructure claim (S3, RDS, VPC, networking)? → Add to environments/{env}/infrastructure/
│  └─ Reference in: infrastructure-claims-apps.yaml
│
├─ Provider authentication config? → Add to shared/configs/provider-configs/
│  └─ Reference in: infrastructure-claims-apps.yaml (dev-provider-configs app)
│
└─ Application workload deployment? → Add to environments/{env}/workloads/
   └─ Reference in: workloads-apps.yaml
```

## File Naming Patterns

### App-of-Apps Files

App-of-apps files deploy multiple child applications and always use the plural `-apps.yaml` suffix:

**Format**: `{layer}-{component}-apps.yaml`

**Examples**:
- `root-apps.yaml` - Entry point that deploys all child app-of-apps
- `crossplane-platform-apps.yaml` - Deploys Crossplane XRDs, Compositions, Providers
- `k8s-platform-services-apps.yaml` - Deploys Kubernetes cluster add-ons
- `infrastructure-claims-apps.yaml` - Deploys infrastructure claims and provider configs
- `workloads-apps.yaml` - Deploys application workloads

**Anti-patterns** (DO NOT USE):
- ❌ `platform-app.yaml` (singular)
- ❌ `services.yaml` (missing -apps suffix)
- ❌ `dev-platform-apps.yaml` (environment in filename, should be in application name only)

### Single Application Files

If creating a standalone application file (not common in app-of-apps pattern), use descriptive hyphenated names without environment prefix:

**Format**: `{component}-app.yaml` (singular for standalone applications)

**Examples**:
- `rbac-app.yaml` - Standalone RBAC configuration (managed separately for security)
- `monitoring-app.yaml` - Standalone monitoring stack

## Application Resource Naming

### Format Pattern

Application resource names in YAML manifests follow this format:

**Format**: `{environment}-{layer}-{component}` OR `{environment}-{component}`

**Components**:
- `environment`: `dev`, `staging`, `prod`
- `layer`: `crossplane`, `k8s`, `infrastructure`, or omitted for workloads
- `component`: Descriptive name (platform, cert-manager, claims, app-name, etc.)

### Examples by Layer

**Crossplane Platform Layer**:
```yaml
metadata:
  name: dev-crossplane-platform        # XRDs, Compositions, Functions
  name: dev-crossplane-providers       # Additional Provider packages
  name: staging-crossplane-platform    # Same resource in staging environment
```

**Kubernetes Platform Services Layer**:
```yaml
metadata:
  name: dev-k8s-cert-manager          # cert-manager
  name: dev-k8s-external-dns          # external-dns
  name: dev-k8s-nginx-ingress         # nginx-ingress
  name: dev-k8s-karpenter             # karpenter autoscaler
```

**Infrastructure Layer**:
```yaml
metadata:
  name: dev-infrastructure-claims     # Infrastructure resource claims
  name: dev-provider-configs          # Provider authentication configs
```

**Workload Layer**:
```yaml
metadata:
  name: dev-s3reader                  # Application workload (no layer prefix)
  name: dev-api-gateway               # Another workload example
```

## Layer Terminology

Clear prefixes distinguish between different infrastructure layers:

### crossplane-

**Scope**: Crossplane infrastructure components
**Deploys from**: `/platform/` directory
**Examples**:
- `dev-crossplane-platform` - XRDs, Compositions, Functions
- `dev-crossplane-providers` - Provider packages (AWS, Helm, Kubernetes)

**When to use**: Anything that extends Crossplane's capabilities or defines infrastructure abstractions

### k8s-

**Scope**: Kubernetes cluster add-ons and platform services
**Deploys from**: `/environments/{env}/platform/` directory
**Examples**:
- `dev-k8s-cert-manager` - Certificate management
- `dev-k8s-external-dns` - DNS automation
- `dev-k8s-nginx-ingress` - Ingress controller
- `dev-k8s-karpenter` - Node autoscaling

**When to use**: Cluster-level services that applications depend on (certificates, ingress, DNS, autoscaling, monitoring)

### infrastructure-

**Scope**: Infrastructure resource claims and provider configurations
**Deploys from**: `/environments/{env}/infrastructure/` and `/shared/configs/provider-configs/`
**Examples**:
- `dev-infrastructure-claims` - S3 buckets, RDS databases, VPCs, networking
- `dev-provider-configs` - AWS authentication via IRSA

**When to use**: Actual infrastructure resources requested from Crossplane platform

### (no prefix for workloads)

**Scope**: Application workloads
**Deploys from**: `/environments/{env}/workloads/`
**Examples**:
- `dev-s3reader` - Application deployment
- `dev-api-service` - API deployment

**When to use**: Application code deployments

## Validation Rules

### Pre-Commit Validation

The following rules should be validated before committing:

1. **App-of-apps files end with `-apps.yaml`** (plural)
   ```bash
   # Valid:
   crossplane-platform-apps.yaml

   # Invalid:
   crossplane-platform-app.yaml  # Missing 's'
   ```

2. **Application names include environment prefix**
   ```yaml
   # Valid:
   metadata:
     name: dev-crossplane-platform

   # Invalid:
   metadata:
     name: crossplane-platform  # Missing environment prefix
   ```

3. **Layer prefixes used correctly**
   ```yaml
   # Valid:
   name: dev-k8s-cert-manager      # Kubernetes service
   name: dev-crossplane-platform   # Crossplane component
   name: dev-s3reader              # Workload (no layer prefix)

   # Invalid:
   name: dev-platform-cert-manager # Ambiguous 'platform' prefix
   ```

4. **No files named `*-app.yaml` (singular) in `argocd/` directory** (except RBAC)
   ```bash
   # Valid:
   environments/dev/argocd/crossplane-platform-apps.yaml
   environments/dev/argocd/rbac-app.yaml  # Exception: security-sensitive

   # Invalid:
   environments/dev/argocd/platform-app.yaml  # Singular
   ```

### Automated Validation Script

```bash
#!/bin/bash
# File: scripts/validate-naming-conventions.sh

set -e

echo "==> Validating ArgoCD naming conventions..."

# Check for app-of-apps file naming
find environments/*/argocd -name "*-app.yaml" -type f 2>/dev/null | while read file; do
    basename=$(basename "$file")
    # Allow rbac-app.yaml as exception
    if [[ "$basename" == "rbac-app.yaml" ]]; then
        continue
    fi

    if [[ ! "$basename" =~ -apps\.yaml$ ]]; then
        echo "❌ ERROR: $file uses singular '-app.yaml' instead of plural '-apps.yaml'"
        echo "   App-of-apps files must end with -apps.yaml"
        exit 1
    fi
done

# Check for valid app-of-apps filenames
find environments/*/argocd -name "*-apps.yaml" -type f 2>/dev/null | while read file; do
    basename=$(basename "$file")
    if [[ ! "$basename" =~ ^(root|crossplane-platform|k8s-platform-services|infrastructure-claims|workloads)-apps\.yaml$ ]]; then
        echo "⚠️  WARNING: $file doesn't match standard naming pattern"
        echo "   Expected: {root|crossplane-platform|k8s-platform-services|infrastructure-claims|workloads}-apps.yaml"
    fi
done

# Validate application names in YAML files
find environments/*/argocd -name "*.yaml" -type f -exec grep -l "kind: Application" {} \; 2>/dev/null | while read file; do
    # Check for environment prefix in application names
    if grep -q "name: " "$file"; then
        grep "name: " "$file" | grep -E "name: (dev|staging|prod)-" > /dev/null || {
            echo "⚠️  WARNING: $file may contain application names without environment prefix"
        }
    fi
done

echo "✅ Naming validation complete"
```

### Optional: Pre-Commit Hook

For enhanced workflow efficiency, you can install the naming validation script as a Git pre-commit hook. This will automatically validate naming conventions before each commit.

#### Installation

The validation script is available at `scripts/pre-commit-naming-validation.sh`. To install it as a pre-commit hook:

```bash
# From the repository root
ln -s ../../scripts/pre-commit-naming-validation.sh .git/hooks/pre-commit
```

#### Verification

Test the hook is installed correctly:

```bash
# The hook should run automatically on commit, but you can test it manually:
./scripts/pre-commit-naming-validation.sh
```

#### What It Checks

The pre-commit hook validates:
1. App-of-apps files use plural `-apps.yaml` suffix
2. App-of-apps filenames match standard patterns
3. Application names include environment prefixes
4. No deprecated patterns (e.g., `root-app.yaml`)
5. No redundant naming patterns (e.g., `application-apps.yaml`)

#### Hook Behavior

- **Critical errors**: Block the commit (exit code 1)
- **Warnings**: Display message but allow commit (exit code 0)
- **Success**: Silent operation with success message

#### Bypassing the Hook

If you need to bypass the hook for a specific commit (not recommended):

```bash
git commit --no-verify -m "Commit message"
```

**Note**: Installing the pre-commit hook is optional but recommended for maintaining naming consistency across the team. The validation script can also be run manually at any time.

## Application Hierarchy

The standardized naming creates a clear four-layer hierarchy:

```
root-apps.yaml (dev-root-apps)
├── crossplane-platform-apps.yaml
│   ├── dev-crossplane-platform (XRDs, Compositions, Functions)
│   └── dev-crossplane-providers (Provider packages)
│
├── infrastructure-claims-apps.yaml
│   ├── dev-infrastructure-claims (Infrastructure resource claims)
│   └── dev-provider-configs (Provider authentication)
│
├── k8s-platform-services-apps.yaml
│   ├── dev-k8s-cert-manager (sync-wave: 10)
│   ├── dev-k8s-external-dns (sync-wave: 20)
│   ├── dev-k8s-nginx-ingress (sync-wave: 30)
│   └── dev-k8s-karpenter (sync-wave: 40)
│
└── workloads-apps.yaml
    └── dev-s3reader (Application deployments)
```

## Sync Wave Ordering

Sync waves control deployment order and ensure dependencies are satisfied:

| Wave | Layer | Applications | Rationale |
|------|-------|--------------|-----------|
| -1 | Crossplane Providers | dev-crossplane-providers | Providers must exist before platform |
| 0 | Crossplane Platform | dev-crossplane-platform | XRDs must exist before infrastructure claims |
| 1 | Infrastructure | dev-infrastructure-claims, dev-provider-configs | Infrastructure must exist before services |
| 10-40 | K8s Platform Services | dev-k8s-cert-manager (10), dev-k8s-external-dns (20), dev-k8s-nginx-ingress (30), dev-k8s-karpenter (40) | Services have internal dependencies |
| 50+ | Workloads | dev-s3reader, etc. | Applications depend on all infrastructure and services |

## Migration from Old Naming

### File Renames

| Old Filename | New Filename | Status |
|-------------|--------------|--------|
| `root-app.yaml` | `root-apps.yaml` | Renamed |
| `platform-apps.yaml` | `crossplane-platform-apps.yaml` | Renamed + Content Merged |
| `providers-app.yaml` | (merged into crossplane-platform-apps.yaml) | Consolidated |
| `infrastructure-apps.yaml` | `infrastructure-claims-apps.yaml` | Renamed |
| `platform-services-app.yaml` | `k8s-platform-services-apps.yaml` | Renamed |
| `workload-apps.yaml` | `workloads-apps.yaml` | Renamed |

### Application Name Changes

| Old Application Name | New Application Name | Rationale |
|---------------------|---------------------|-----------|
| `dev-root` | `dev-root-apps` | Consistency with file naming |
| `dev-platform-crossplane` | `dev-crossplane-platform` | Layer-first naming |
| `dev-additional-providers` | `dev-crossplane-providers` | Clear Crossplane association |
| `dev-infrastructure` | `dev-infrastructure-claims` | Clarify these are resource requests |
| `dev-provider-configs` | (unchanged) | Already clear |
| `dev-platform-cert-manager` | `dev-k8s-cert-manager` | Distinguish K8s from Crossplane platform |
| `dev-platform-external-dns` | `dev-k8s-external-dns` | Distinguish K8s from Crossplane platform |
| `dev-platform-nginx-ingress` | `dev-k8s-nginx-ingress` | Distinguish K8s from Crossplane platform |
| `dev-platform-karpenter` | `dev-k8s-karpenter` | Distinguish K8s from Crossplane platform |
| `dev-workload-s3reader` | `dev-s3reader` | Simpler naming for workloads |

## Best Practices

### DO:
- ✅ Use environment prefix for all application names (`dev-`, `staging-`, `prod-`)
- ✅ Use layer-specific prefixes (`crossplane-`, `k8s-`, `infrastructure-`)
- ✅ Use plural `-apps.yaml` for app-of-apps files
- ✅ Keep filenames lowercase with hyphens (kebab-case)
- ✅ Make names self-documenting and descriptive
- ✅ Validate naming conventions before committing

### DON'T:
- ❌ Mix singular and plural in app-of-apps filenames
- ❌ Omit environment prefix from application names
- ❌ Use ambiguous prefixes like `platform-` (use `crossplane-` or `k8s-`)
- ❌ Include environment name in filenames (only in application names)
- ❌ Use underscores or camelCase in filenames
- ❌ Create overly abbreviated or cryptic names

## Examples

### Adding a New Kubernetes Service (Prometheus)

1. **Create manifests**: `environments/dev/platform/prometheus/`
2. **Add to app-of-apps**: Edit `k8s-platform-services-apps.yaml`
3. **Application name**: `dev-k8s-prometheus`
4. **Sync wave**: Assign appropriate wave based on dependencies

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-k8s-prometheus
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "50"  # After ingress
spec:
  project: default
  source:
    repoURL: git@github.com:ims-platform-dev/portal-kombat.git
    targetRevision: main
    path: environments/dev/platform/prometheus
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Adding a New Infrastructure Claim (RDS Database)

1. **Create claim**: `environments/dev/infrastructure/database/postgres.yaml`
2. **Reference in**: `infrastructure-claims-apps.yaml` (already includes `/infrastructure` recursively)
3. **Application**: `dev-infrastructure-claims` (no change needed)

### Adding a New Workload (API Service)

1. **Create manifests**: `environments/dev/workloads/api-service/`
2. **Add to app-of-apps**: Edit `workloads-apps.yaml`
3. **Application name**: `dev-api-service`

```yaml
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev-api-service
  namespace: argocd
spec:
  project: default
  source:
    repoURL: git@github.com:ims-platform-dev/portal-kombat.git
    targetRevision: main
    path: environments/dev/workloads/api-service
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Troubleshooting

### Application Not Deploying

**Issue**: New application doesn't appear in ArgoCD

**Check**:
1. Is the application included in the correct app-of-apps file?
2. Does the application name match the pattern `{env}-{layer}-{component}`?
3. Has the parent app-of-apps been synced?
4. Check ArgoCD logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`

### Naming Validation Failing

**Issue**: Pre-commit hook or validation script reports errors

**Check**:
1. Are all app-of-apps files using `-apps.yaml` (plural)?
2. Do all application names include environment prefix?
3. Are layer prefixes correct (`crossplane-`, `k8s-`, `infrastructure-`)?
4. Run validation script manually: `bash scripts/validate-naming-conventions.sh`

## References

- [ArgoCD App-of-Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [GitOps Principles](https://opengitops.dev/)
- Repository Architecture: [docs/ARCHITECTURE.md](./ARCHITECTURE.md)
- Quick Start Guide: [docs/QUICK-START.md](./QUICK-START.md)
