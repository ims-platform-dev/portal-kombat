# Migration Summary: Old Structure → New Structure

## What Changed

Your repository has been reorganized from a flat structure to an **environment-first** organization pattern that scales to multi-environment, multi-region, and multi-account deployments.

## Directory Mapping

### Old Structure → New Structure

| Old Location | New Location | Notes |
|-------------|--------------|-------|
| `workloads/monitoring/` | `environments/dev/platform/monitoring/` | Platform service |
| `workloads/s3reader/` | `environments/dev/workloads/s3reader/` | Application workload |
| `examples/crossplane/` | Kept as-is | Reference examples |
| `iam-policies/` | `shared/managed-resources/iam-roles/` | Shared IAM resources |
| `bootstrap/crossplane/` | Kept + New ArgoCD apps | Old bootstrap preserved, new apps created |
| `apps/` | Kept as-is | Legacy - can be removed later |

### New Additions

| Location | Purpose |
|----------|---------|
| `platform/providers/` | Crossplane provider packages |
| `platform/xrds/` | Infrastructure API definitions (XRDs) |
| `platform/compositions/` | Infrastructure implementations |
| `environments/dev/argocd/` | ArgoCD Applications (App of Apps pattern) |
| `environments/dev/infrastructure/` | Infrastructure claims (what to create) |
| `shared/configs/provider-configs/` | AWS account configurations |
| `docs/` | Comprehensive documentation |

## Key Improvements

### 1. Clear Separation of Concerns

**Before**: Everything mixed together in `workloads/`, `bootstrap/`, `examples/`

**After**:
- **Platform layer**: Define infrastructure capabilities once
- **Environment layer**: Use those capabilities per environment
- **Shared layer**: Cross-environment resources

### 2. Environment-First Organization

**Before**: Hard to add new environments, unclear what belongs where

**After**:
```
environments/dev/     # Everything for dev
environments/staging/ # Future: Copy dev structure
environments/prod/    # Future: Copy dev structure
```

### 3. Crossplane Best Practices

**Before**: Only direct AWS resources (Managed Resources)

**After**:
- **XRDs**: User-friendly APIs (e.g., "ObjectStorage")
- **Compositions**: Implementations with best practices baked in
- **Claims**: Simple way to request infrastructure

### 4. ArgoCD App-of-Apps Pattern

**Before**: Individual ArgoCD Applications managed manually

**After**: Single root application that manages everything:
```
root-app.yaml
  ├── platform-apps.yaml (Crossplane)
  ├── infrastructure-apps.yaml (VPC, EKS, S3)
  └── workload-apps.yaml (Applications)
```

## What to Do Next

### Step 1: Review the New Structure

Take a few minutes to explore:
```bash
# See the platform definitions
ls platform/xrds/
ls platform/compositions/

# See dev environment
ls environments/dev/
ls environments/dev/argocd/
ls environments/dev/infrastructure/
```

### Step 2: Update Your GitHub Repository Reference

The ArgoCD applications reference `git@github.com:ims-platform-dev/portal-kombat.git`. If this has changed, update:
```bash
find environments/dev/argocd/ -name "*.yaml" -exec sed -i '' 's|OLD_REPO_URL|NEW_REPO_URL|g' {} +
```

### Step 3: Test the New Structure

**Option A: Fresh Deployment** (Recommended for testing)
```bash
# Deploy to a test cluster
kubectl apply -f environments/dev/argocd/root-app.yaml

# Watch it deploy
kubectl get applications -n argocd -w
```

**Option B: Gradual Migration** (Safer for production)
```bash
# Deploy just the platform first
kubectl apply -f environments/dev/argocd/platform-apps.yaml

# Then infrastructure
kubectl apply -f environments/dev/argocd/infrastructure-apps.yaml

# Then workloads
kubectl apply -f environments/dev/argocd/workload-apps.yaml
```

### Step 4: Create Your First Infrastructure with Compositions

Try creating an S3 bucket using the new platform API:

```bash
# Review the example
cat environments/dev/infrastructure/storage/example-bucket-claim.yaml

# Update the bucket name (must be globally unique!)
# Then apply
kubectl apply -f environments/dev/infrastructure/storage/example-bucket-claim.yaml

# Watch it get created
kubectl get objectstorage -w
kubectl get buckets
```

### Step 5: Read the Documentation

- **[Architecture](ARCHITECTURE.md)** - Understand the full design
- **[Quick Start](QUICK-START.md)** - Step-by-step guide
- **[README](../README.md)** - Overview and examples

### Step 6: Plan Your Next XRDs

Think about what infrastructure you need:
- VPC (network) - Define once, use for all environments
- EKS clusters (compute) - Dev, staging, prod configurations
- RDS databases (database) - Small for dev, HA for prod
- More S3 buckets (storage) - Various access patterns

Create XRDs and Compositions for these in `platform/`, then claim them in `environments/dev/infrastructure/`.

## Migration Checklist

- [ ] Review new directory structure
- [ ] Update GitHub repo URLs in ArgoCD apps (if needed)
- [ ] Test deployment in dev cluster
- [ ] Verify Crossplane providers install successfully
- [ ] Create a test S3 bucket using the composition
- [ ] Migrate any custom resources to new locations
- [ ] Update team documentation with new structure
- [ ] Plan staging environment structure
- [ ] Plan production environment structure

## Old Directories (Can Be Removed Later)

These directories are kept for reference but can be removed once you're comfortable:

```bash
# After verifying new structure works:
# git rm -r apps/
# git rm -r workloads/
# git rm -r bootstrap/crossplane/  # Keep only if you need the old bootstrap process
```

**Recommendation**: Keep them for 1-2 weeks while you get comfortable with the new structure.

## Common Questions

### Q: What happened to my workloads?

**A**: They moved to `environments/dev/workloads/` and `environments/dev/platform/`.
- Applications → `environments/dev/workloads/`
- Platform services (monitoring, ingress) → `environments/dev/platform/`

### Q: How do I add staging?

**A**: Copy the dev structure:
```bash
cp -r environments/dev environments/staging
# Update configs, bucket names, etc.
# Update ArgoCD apps to point to staging paths
kubectl apply -f environments/staging/argocd/root-app.yaml
```

### Q: Can I still use direct AWS resources (Managed Resources)?

**A**: Yes! Put them in:
- `shared/managed-resources/` for cross-environment resources
- `environments/dev/infrastructure/` for dev-specific resources

### Q: Do I have to use Compositions?

**A**: No, but they're recommended for:
- Resources you'll create multiple times
- Standard configurations (e.g., "secure S3 bucket")
- Bundling multiple resources together

Start with Managed Resources, graduate to Compositions when you see patterns.

### Q: What about the examples directory?

**A**: Keep it! It's useful for reference. The new structure adds real templates you can use, but examples are still valuable.

## Troubleshooting

### ArgoCD can't find paths

**Symptom**: ArgoCD shows "Path not found" errors

**Fix**: Check the `repoURL` and `path` in ArgoCD Application manifests match your repo structure.

### Crossplane providers not installing

**Symptom**: Providers stuck in "Installing"

**Fix**: Check Crossplane core is installed:
```bash
kubectl get pods -n crossplane-system
kubectl logs -n crossplane-system -l app=crossplane
```

### Claims stuck in "Not Ready"

**Symptom**: ObjectStorage claim never becomes Ready

**Fix**:
1. Check provider is healthy: `kubectl get providers`
2. Check provider config: `kubectl get providerconfigs -A`
3. Check AWS permissions (IAM role)
4. Check provider logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3`

## Getting Help

If you run into issues:
1. Check the logs: `kubectl logs -n argocd ...` or `kubectl logs -n crossplane-system ...`
2. Review the docs: `docs/ARCHITECTURE.md`, `docs/QUICK-START.md`
3. Check ArgoCD UI: `argocd app list`, `argocd app get <app-name>`
4. Verify IAM: `shared/managed-resources/iam-roles/SETUP-INSTRUCTIONS.md`

## Summary

You now have a **production-ready GitOps repository structure** that:
- ✅ Scales to multiple environments
- ✅ Supports multi-region and multi-account
- ✅ Uses Crossplane best practices (XRDs + Compositions)
- ✅ Follows GitOps with ArgoCD app-of-apps
- ✅ Has clear separation of concerns
- ✅ Is well-documented

**Next step**: Test it out! Deploy the root app and watch ArgoCD work its magic.
