# ArgoCD Application Migration Map

## Overview

This document provides a complete mapping of file renames and application name changes for the GitOps repository structure standardization. Use this as a reference during migration and for tracking changes in Git history.

## File Renames

| Old Filename | New Filename | Status |
|-------------|--------------|--------|
| root-app.yaml | root-apps.yaml | Renamed |
| platform-apps.yaml | crossplane-platform-apps.yaml | Renamed + Content Merged |
| providers-app.yaml | _providers-app.yaml.old | Archived (merged into crossplane-platform-apps.yaml) |
| infrastructure-apps.yaml | infrastructure-claims-apps.yaml | Renamed + Content Consolidated |
| platform-services-app.yaml | k8s-platform-services-apps.yaml | Renamed |
| workload-apps.yaml | workloads-apps.yaml | Renamed |

## Application Name Changes

| Old Application Name | New Application Name | File Location |
|---------------------|---------------------|---------------|
| dev-root | dev-root-apps | root-apps.yaml |
| dev-platform-crossplane | dev-crossplane-platform | crossplane-platform-apps.yaml |
| dev-additional-providers | dev-crossplane-providers | crossplane-platform-apps.yaml |
| dev-infrastructure | dev-infrastructure-claims | infrastructure-claims-apps.yaml |
| dev-provider-configs | dev-provider-configs (unchanged) | infrastructure-claims-apps.yaml |
| dev-platform-cert-manager | dev-k8s-cert-manager | k8s-platform-services-apps.yaml |
| dev-platform-external-dns | dev-k8s-external-dns | k8s-platform-services-apps.yaml |
| dev-platform-nginx-ingress | dev-k8s-nginx-ingress | k8s-platform-services-apps.yaml |
| dev-platform-karpenter | dev-k8s-karpenter | k8s-platform-services-apps.yaml |
| dev-workload-s3reader | dev-s3reader | workloads-apps.yaml |

## Naming Convention Rationale

### App-of-Apps Suffix
All files that deploy multiple applications use the `-apps.yaml` suffix (plural) to clearly indicate they are app-of-apps patterns:
- `root-apps.yaml` - Deploys child app-of-apps
- `crossplane-platform-apps.yaml` - Deploys Crossplane components
- `infrastructure-claims-apps.yaml` - Deploys infrastructure claims
- `k8s-platform-services-apps.yaml` - Deploys Kubernetes services
- `workloads-apps.yaml` - Deploys application workloads

### Layer Prefixes
Clear prefixes distinguish between different infrastructure layers:
- **crossplane-**: Crossplane infrastructure (XRDs, Compositions, Providers)
- **k8s-**: Kubernetes platform services (cert-manager, ingress, DNS, autoscaling)
- **infrastructure-**: Infrastructure resource claims and provider configs
- **workloads-**: Application deployments (no layer prefix needed in app names)

### Environment Prefixes
All ArgoCD Application resources include environment prefix for clarity:
- `dev-crossplane-platform` (not just `crossplane-platform`)
- `staging-k8s-cert-manager` (not just `cert-manager`)
- `prod-infrastructure-claims` (not just `infrastructure-claims`)

## Git History Tracking

### Tracking Renamed Files

For files that were renamed, use `git log --follow` to track full history:

```bash
# Track history of renamed files
git log --follow environments/dev/argocd/root-apps.yaml
git log --follow environments/dev/argocd/crossplane-platform-apps.yaml
git log --follow environments/dev/argocd/infrastructure-claims-apps.yaml
git log --follow environments/dev/argocd/k8s-platform-services-apps.yaml
git log --follow environments/dev/argocd/workloads-apps.yaml
```

### Tracking Merged Content

For `providers-app.yaml` which was merged into `crossplane-platform-apps.yaml`:

```bash
# View original providers-app.yaml history
git log -- environments/dev/argocd/providers-app.yaml

# View combined history after merge
git log --follow environments/dev/argocd/crossplane-platform-apps.yaml
```

### Tracking Specific Application Name Changes

```bash
# Find commits that changed application names
git log -p --all -S "dev-platform-crossplane"
git log -p --all -S "dev-crossplane-platform"

# See all changes to a specific app name
git log -p --all --grep="dev-k8s-cert-manager"
```

### Finding Original Commit

```bash
# Find when files were originally created
git log --diff-filter=A -- environments/dev/argocd/platform-apps.yaml
git log --diff-filter=A -- environments/dev/argocd/providers-app.yaml
```

## Migration Verification Commands

### Pre-Migration State Capture

```bash
# Capture current application list
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status > pre-migration-apps.txt

# Backup all ArgoCD applications
kubectl get applications -n argocd -o yaml > argocd-backup-$(date +%Y%m%d-%H%M%S).yaml

# List current files
ls -la environments/dev/argocd/ > pre-migration-files.txt
```

### Post-Migration Verification

```bash
# Capture new application list
kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,HEALTH:.status.health.status,SYNC:.status.sync.status > post-migration-apps.txt

# Compare before and after
diff pre-migration-apps.txt post-migration-apps.txt

# Verify new file structure
ls -la environments/dev/argocd/

# Verify all apps are healthy
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.health.status}{"\t"}{.status.sync.status}{"\n"}{end}'
```

## Rollback Commands

If migration issues occur:

```bash
# Option 1: Revert the Git commit
git revert HEAD
git push origin main

# Option 2: Restore from backup
kubectl apply -f argocd-backup-YYYYMMDD-HHMMSS.yaml

# Option 3: Manual rollback of root application
kubectl delete application dev-root-apps -n argocd
kubectl apply -f backup/root-app.yaml.backup
```

## Application Hierarchy After Migration

```
dev-root-apps (root-apps.yaml)
├── dev-crossplane-platform (crossplane-platform-apps.yaml)
│   ├── Deploys: XRDs, Compositions, Functions
│   └── Path: platform/
├── dev-crossplane-providers (crossplane-platform-apps.yaml)
│   ├── Deploys: Additional Crossplane providers
│   └── Path: platform/providers/
├── dev-infrastructure-claims (infrastructure-claims-apps.yaml)
│   ├── Deploys: Infrastructure resource claims
│   └── Path: environments/dev/infrastructure/
├── dev-provider-configs (infrastructure-claims-apps.yaml)
│   ├── Deploys: Provider authentication configs
│   └── Path: shared/configs/provider-configs/
├── dev-k8s-cert-manager (k8s-platform-services-apps.yaml)
│   ├── Deploys: Certificate management
│   └── Path: environments/dev/platform/cert-manager/
├── dev-k8s-external-dns (k8s-platform-services-apps.yaml)
│   ├── Deploys: DNS automation
│   └── Path: environments/dev/platform/external-dns/
├── dev-k8s-nginx-ingress (k8s-platform-services-apps.yaml)
│   ├── Deploys: Ingress controller
│   └── Path: environments/dev/platform/nginx-ingress/
├── dev-k8s-karpenter (k8s-platform-services-apps.yaml)
│   ├── Deploys: Node autoscaling
│   └── Path: environments/dev/platform/karpenter/
└── dev-s3reader (workloads-apps.yaml)
    ├── Deploys: Application workload
    └── Path: environments/dev/workloads/s3reader/
```

## Key Consolidations

### Crossplane Platform Apps
**Before**: Two separate files
- `platform-apps.yaml` → XRDs and Compositions
- `providers-app.yaml` → Additional providers

**After**: Single file with two applications
- `crossplane-platform-apps.yaml`:
  - `dev-crossplane-platform` (XRDs, Compositions, Functions)
  - `dev-crossplane-providers` (Providers)

**Rationale**: Both components are part of the Crossplane platform layer, logically grouped together.

### Infrastructure Claims Apps
**Before**: Content split across files
- `infrastructure-apps.yaml` → Infrastructure claims
- Separate file for provider configs

**After**: Single file with consolidated applications
- `infrastructure-claims-apps.yaml`:
  - `dev-infrastructure-claims` (Infrastructure resource claims)
  - `dev-provider-configs` (Provider authentication)

**Rationale**: Infrastructure claims require provider configs to function, logical grouping.

## RBAC Handling

**Decision**: RBAC remains separate from app-of-apps pattern for security.

- `rbac-app.yaml` is **not renamed**
- Removed from `root-apps.yaml` include directive
- Applied manually or via dedicated ArgoCD application
- Rationale: Security-critical changes should be explicit and carefully reviewed

## Deployment Order (Sync Waves)

Sync wave ordering is preserved after migration:

| Sync Wave | Component | Application Names |
|-----------|-----------|------------------|
| -1 | Crossplane Providers | dev-crossplane-providers |
| 0 | Crossplane Platform | dev-crossplane-platform |
| 1+ | Infrastructure | dev-infrastructure-claims, dev-provider-configs |
| 10 | cert-manager | dev-k8s-cert-manager |
| 20 | external-dns | dev-k8s-external-dns |
| 30 | nginx-ingress | dev-k8s-nginx-ingress |
| 40 | karpenter | dev-k8s-karpenter |
| 50+ | Workloads | dev-s3reader |

## Related Documentation

- [Naming Conventions](./NAMING_CONVENTIONS.md) - Detailed naming rules and patterns
- [Design Document](../.claude/specs/gitops-structure-standardization/design.md) - Complete design specification
- [CLAUDE.md](../CLAUDE.md) - Updated operational commands and patterns
- [README.md](../README.md) - High-level project overview with new structure

## Migration Timeline Reference

1. **Phase 1: Planning** - Design approval, backup creation
2. **Phase 2: File Renaming** - Execute git mv commands
3. **Phase 3: Content Updates** - Update application names and references
4. **Phase 4: Testing** - Validation, ArgoCD diff, dry-run
5. **Phase 5: Deployment** - Merge to main, monitor sync
6. **Phase 6: Verification** - Test infrastructure, services, workloads
7. **Phase 7: Cleanup** - Remove old applications, update documentation

## Notes

- All changes made in atomic Git commit for easy rollback
- Zero-downtime migration with rollback capability
- Git history fully preserved using `git mv` commands
- Application specs (source, destination, syncPolicy) remain identical
- Only metadata.name fields and filenames change
- All infrastructure claims, platform services, and workload manifests remain in current locations
