# Post-Merge Verification Checklist

This checklist should be executed after merging the GitOps naming standardization changes to verify that ArgoCD applications are functioning correctly with the new naming conventions.

**Branch**: `gitops/standardize-naming` → `main`
**PR**: [Link to PR]
**Merge Date**: [Date]

## Pre-Verification Setup

### 1. Verify Merge Status

```bash
# Ensure you're on main branch
git checkout main
git pull origin main

# Verify merge commit
git log --oneline -1

# Check for any conflicts or pending changes
git status
```

**Expected**: Clean working directory, latest commit shows merge

---

## ArgoCD Application Health Checks

### 2. Check ArgoCD Server Status

```bash
# Verify ArgoCD is running
kubectl get pods -n argocd

# Check ArgoCD Application Controller logs for errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

**Expected**: All ArgoCD pods in Running state, no critical errors in logs

### 3. List All Applications

```bash
# Get all ArgoCD applications
kubectl get applications -n argocd

# Check application sync status
kubectl get applications -n argocd -o wide
```

**Expected Output**:
```
NAME                              SYNC STATUS   HEALTH STATUS
dev-root-apps                     Synced        Healthy
dev-crossplane-platform           Synced        Healthy
dev-crossplane-providers          Synced        Healthy
dev-infrastructure-claims         Synced        Healthy
dev-provider-configs              Synced        Healthy
dev-k8s-cert-manager             Synced        Healthy
dev-k8s-external-dns             Synced        Healthy
dev-k8s-nginx-ingress            Synced        Healthy
dev-k8s-karpenter                Synced        Healthy
dev-s3reader                      Synced        Healthy
```

**Checklist**:
- [ ] `dev-root-apps` exists and is Synced
- [ ] `dev-crossplane-platform` exists and is Synced
- [ ] `dev-crossplane-providers` exists and is Synced
- [ ] `dev-infrastructure-claims` exists and is Synced
- [ ] `dev-provider-configs` exists and is Synced
- [ ] `dev-k8s-cert-manager` exists and is Synced
- [ ] `dev-k8s-external-dns` exists and is Synced
- [ ] `dev-k8s-nginx-ingress` exists and is Synced
- [ ] `dev-k8s-karpenter` exists and is Synced
- [ ] `dev-s3reader` exists and is Synced (if deployed)

### 4. Verify Root Application

```bash
# Check root-apps application details
kubectl describe application dev-root-apps -n argocd

# Verify root-apps is watching the correct source path
kubectl get application dev-root-apps -n argocd -o jsonpath='{.spec.source.path}'
```

**Expected**:
- Path: `environments/dev/argocd`
- File: `root-apps.yaml` (not `root-app.yaml`)
- Status: Synced and Healthy

**Checklist**:
- [ ] Root application name is `dev-root-apps`
- [ ] Source path points to correct location
- [ ] No sync errors

### 5. Verify Crossplane Applications

```bash
# Check Crossplane platform application
kubectl describe application dev-crossplane-platform -n argocd

# Check Crossplane providers application
kubectl describe application dev-crossplane-providers -n argocd

# Verify Crossplane providers are healthy
kubectl get providers
```

**Expected**:
- Both applications Synced and Healthy
- All Crossplane providers installed and healthy

**Checklist**:
- [ ] `dev-crossplane-platform` is Synced
- [ ] `dev-crossplane-providers` is Synced
- [ ] All providers show as HEALTHY and INSTALLED

### 6. Verify Kubernetes Platform Services

```bash
# Check each K8s platform service application
for app in dev-k8s-cert-manager dev-k8s-external-dns dev-k8s-nginx-ingress dev-k8s-karpenter; do
    echo "=== Checking $app ==="
    kubectl describe application $app -n argocd | grep -A 5 "Status:"
    echo ""
done

# Verify actual services are running
kubectl get pods -n cert-manager
kubectl get pods -n external-dns
kubectl get pods -n nginx-ingress
kubectl get pods -n karpenter
```

**Expected**: All K8s platform services deployed and running

**Checklist**:
- [ ] cert-manager pods running
- [ ] external-dns pods running
- [ ] nginx-ingress pods running
- [ ] karpenter pods running (if enabled)

### 7. Verify Infrastructure Applications

```bash
# Check infrastructure claims application
kubectl describe application dev-infrastructure-claims -n argocd

# Check provider configs application
kubectl describe application dev-provider-configs -n argocd

# Verify provider configs exist
kubectl get providerconfigs
```

**Expected**: Infrastructure and provider config applications Synced

**Checklist**:
- [ ] `dev-infrastructure-claims` is Synced
- [ ] `dev-provider-configs` is Synced
- [ ] ProviderConfigs are present

### 8. Verify Workload Applications

```bash
# Check workload applications (if any deployed)
kubectl describe application dev-s3reader -n argocd

# Verify workload pods
kubectl get pods -n default -l app=s3reader
```

**Expected**: Workload applications (if deployed) are Synced and Healthy

**Checklist**:
- [ ] All workload applications are Synced
- [ ] Workload pods are running

---

## Application Sync Wave Verification

### 9. Verify Sync Wave Order

```bash
# Check sync waves are applied correctly
kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.argocd\.argoproj\.io/sync-wave}{"\n"}{end}' | sort -k2 -n
```

**Expected Order**:
```
dev-crossplane-providers       -1
dev-crossplane-platform         0
dev-infrastructure-claims       1
dev-provider-configs            1
dev-k8s-cert-manager           10
dev-k8s-external-dns           20
dev-k8s-nginx-ingress          30
dev-k8s-karpenter              40
dev-s3reader                   50+
```

**Checklist**:
- [ ] Providers deploy first (wave -1)
- [ ] Platform deploys second (wave 0)
- [ ] Infrastructure deploys third (wave 1)
- [ ] K8s services deploy in correct order (waves 10-40)
- [ ] Workloads deploy last (wave 50+)

---

## Application Events and Errors

### 10. Check for Application Errors

```bash
# Check for failed sync operations
kubectl get applications -n argocd | grep -v "Synced.*Healthy"

# Check ArgoCD events for errors
kubectl get events -n argocd --sort-by='.lastTimestamp' | grep -i error

# Check application-specific errors
for app in $(kubectl get applications -n argocd -o name); do
    echo "=== $app ==="
    kubectl get $app -n argocd -o jsonpath='{.status.conditions[?(@.type=="SyncError")]}' | jq .
done
```

**Expected**: No sync errors or health issues

**Checklist**:
- [ ] No applications in OutOfSync state
- [ ] No applications in Unhealthy state
- [ ] No SyncError conditions present

---

## Resource Validation

### 11. Verify Crossplane Resources

```bash
# Check Crossplane managed resources
kubectl get managed

# Check for any resources in failed state
kubectl get managed -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True"))'

# Verify claims are bound
kubectl get objectstorage
```

**Expected**: All managed resources Ready, all claims Bound

**Checklist**:
- [ ] All Crossplane managed resources show as Ready
- [ ] All claims show as Bound
- [ ] No resources in Failed state

### 12. Verify Kubernetes Resources

```bash
# Check for certificates (cert-manager)
kubectl get certificates --all-namespaces

# Check for ingress resources
kubectl get ingress --all-namespaces

# Check DNS records (if external-dns deployed)
kubectl get dnsrecord --all-namespaces 2>/dev/null || echo "No DNSRecord CRD"
```

**Expected**: Resources created as expected per application manifests

**Checklist**:
- [ ] Certificates issued successfully
- [ ] Ingress resources created
- [ ] DNS records created (if applicable)

---

## Performance Baseline

### 13. Measure Sync Performance

```bash
# Time a full sync of root application
time kubectl patch application dev-root-apps -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Monitor sync progress
watch kubectl get applications -n argocd
```

**Performance Baseline**:
- Full sync time: ____ seconds
- Average application sync time: ____ seconds

**Checklist**:
- [ ] Full sync completes in reasonable time (<5 minutes)
- [ ] No applications stuck in "Progressing" state
- [ ] No timeout errors

---

## Naming Convention Validation

### 14. Run Naming Validation Script

```bash
# Run pre-commit validation script
./scripts/pre-commit-naming-validation.sh

# Verify no old naming patterns exist
grep -r "root-app\.yaml" environments/dev/argocd || echo "✅ No old patterns found"

# Verify all app-of-apps use plural suffix
find environments/dev/argocd -name "*-apps.yaml" -type f
```

**Expected**: Validation script passes, no old patterns detected

**Checklist**:
- [ ] Naming validation script passes
- [ ] All app-of-apps files use `-apps.yaml` suffix
- [ ] No references to old naming patterns
- [ ] All application names follow `{env}-{layer}-{component}` pattern

---

## ArgoCD UI Verification

### 15. Visual Verification in ArgoCD UI

```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port-forward to ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Access ArgoCD UI at: https://localhost:8080

**UI Checklist**:
- [ ] All applications visible in UI
- [ ] Application names display correctly
- [ ] Sync status shows correctly
- [ ] Health status shows correctly
- [ ] Application hierarchy displays properly
- [ ] No orphaned or missing applications

---

## Rollback Procedure (If Issues Found)

### 16. Emergency Rollback Steps

**If critical issues are found during verification:**

```bash
# Option 1: Revert the merge commit
git revert -m 1 <merge-commit-hash>
git push origin main

# Option 2: Restore previous root-app.yaml
git show <commit-before-merge>:environments/dev/argocd/root-app.yaml > environments/dev/argocd/root-apps.yaml
kubectl apply -f environments/dev/argocd/root-apps.yaml

# Option 3: Manual ArgoCD application restoration
# Restore application manifests from previous commit
git checkout <commit-before-merge> -- environments/dev/argocd/

# Apply restored manifests
kubectl apply -f environments/dev/argocd/ -R

# Force sync all applications
for app in $(kubectl get applications -n argocd -o name); do
    kubectl patch $app -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
done
```

**Rollback Checklist**:
- [ ] Identify root cause of failure
- [ ] Document failure symptoms
- [ ] Execute appropriate rollback procedure
- [ ] Verify system returns to stable state
- [ ] Create issue for investigation

---

## Sign-Off

### Verification Complete

**Date**: _______________
**Verified By**: _______________
**Result**: ✅ PASS / ❌ FAIL

**Issues Found**:
- [ ] None
- [ ] Minor (documented below)
- [ ] Major (requires rollback)

**Notes**:
```
[Add any observations, warnings, or issues found during verification]
```

**Action Items**:
1. [ ] Update monitoring dashboards if needed
2. [ ] Notify team of successful merge
3. [ ] Archive this checklist with results
4. [ ] Update runbooks if procedures changed

---

## Additional Resources

- **Naming Conventions**: [docs/NAMING_CONVENTIONS.md](./NAMING_CONVENTIONS.md)
- **Architecture**: [docs/ARCHITECTURE.md](./ARCHITECTURE.md)
- **Troubleshooting**: [docs/TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **ArgoCD Documentation**: https://argo-cd.readthedocs.io/

---

**Document Version**: 1.0
**Last Updated**: 2025-11-04
**Maintained By**: Platform Engineering Team
