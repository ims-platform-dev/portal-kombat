# Crossplane v2.0 Migration Quick Start

**Status**: ✅ Ready to Deploy
**Estimated Time**: 1-2 hours
**Risk Level**: MEDIUM

---

## 🚀 Quick Deployment

### 1. Pre-Migration Backup (5 minutes)

```bash
# Create backup directory
mkdir -p ~/crossplane-v2-backup

# Backup current state
kubectl get providers -o yaml > ~/crossplane-v2-backup/providers.yaml
kubectl get xrd -o yaml > ~/crossplane-v2-backup/xrds.yaml
kubectl get compositions -o yaml > ~/crossplane-v2-backup/compositions.yaml
kubectl get managed -o wide > ~/crossplane-v2-backup/managed-resources.txt

# Document current version
kubectl get pods -n crossplane-system -l app=crossplane -o jsonpath='{.items[0].spec.containers[0].image}' > ~/crossplane-v2-backup/current-version.txt

echo "✅ Backup complete: ~/crossplane-v2-backup/"
```

---

### 2. Apply Migration (10-15 minutes)

```bash
# Navigate to repository
cd /Users/austincarter/Development/personal/portal-kombat

# Review changes
git status
git diff bootstrap/crossplane/Chart.yaml
git diff bootstrap/eks-bootstrap/values/crossplane.yaml
git diff platform/providers/upjet-aws-eks.yaml

# Commit changes
git add .
git commit -m "feat: migrate to Crossplane v2.0.2 with provider updates

- Upgrade Crossplane core v1.10.1 → v2.0.2
- Install function-patch-and-transform v0.6.0
- Update AWS providers to v2.1.1
- Clean up feature flags for GA features
- Add comprehensive verification documentation

BREAKING CHANGE: Major Crossplane version upgrade
Ref: docs/CROSSPLANE-V2-MIGRATION-SUMMARY.md"

# Push to feature branch (recommended)
git checkout -b feature/crossplane-v2-migration
git push origin feature/crossplane-v2-migration

# OR push directly to main (if you have workflow approval)
# git push origin main
```

---

### 3. Trigger ArgoCD Sync (5 minutes)

**Option A: ArgoCD UI**
```
1. Open ArgoCD UI
2. Navigate to root application
3. Click "Sync" → "Synchronize"
4. Watch sync progress
```

**Option B: kubectl**
```bash
# Force sync root application
kubectl patch application root-app -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Watch sync status
kubectl get applications -n argocd -w
```

**Option C: ArgoCD CLI**
```bash
# Sync root application
argocd app sync root-app

# Watch progress
argocd app wait root-app --sync
```

---

### 4. Quick Verification (10 minutes)

```bash
# Check Crossplane version (should show v2.0.2)
kubectl get pods -n crossplane-system -l app=crossplane -o jsonpath='{.items[0].spec.containers[0].image}'

# Check all pods running
kubectl get pods -n crossplane-system

# Check function installed
kubectl get functions
# Expected: function-patch-and-transform INSTALLED=True, HEALTHY=True

# Check providers healthy
kubectl get providers
# All should show INSTALLED=True, HEALTHY=True

# Check XRDs available
kubectl get xrd
# All should show ESTABLISHED=True, OFFERED=True
```

**Quick Pass/Fail**:
- ✅ PASS: All commands return expected output
- ❌ FAIL: Any component shows unhealthy → See troubleshooting

---

### 5. Test Resource Creation (5 minutes)

```bash
# Create test S3 bucket
cat <<EOF | kubectl apply -f -
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: ObjectStorage
metadata:
  name: v2-test-$(date +%s)
  namespace: default
spec:
  parameters:
    bucketName: portal-kombat-test-$(date +%s)
    region: us-east-2
    versioning: true
    environment: dev
EOF

# Watch claim become Ready (takes ~2-3 minutes)
kubectl get objectstorage -w

# Cleanup
kubectl delete objectstorage v2-test-$(date +%s)
```

**Success**: Claim reaches Ready=True
**Failure**: Claim stuck or error → See troubleshooting

---

## 🆘 Emergency Rollback

If critical issues occur:

```bash
# Rollback Crossplane core
helm rollback crossplane -n crossplane-system

# Restore previous providers
kubectl apply -f ~/crossplane-v2-backup/providers.yaml

# Remove function
kubectl delete function function-patch-and-transform

# Verify rollback
kubectl get providers
kubectl get managed
```

---

## 📚 Detailed Guides

For comprehensive verification:
- **Full Guide**: `docs/CROSSPLANE-V2-MIGRATION-VERIFICATION.md`
- **Summary**: `docs/CROSSPLANE-V2-MIGRATION-SUMMARY.md`

---

## 🎯 Success Criteria

Migration is successful when:
- ✅ Crossplane v2.0.2 running
- ✅ Function installed and healthy
- ✅ All providers v2.1.1 and healthy
- ✅ Test claim reaches Ready state
- ✅ Existing resources unaffected

---

## 📝 Files Changed

```
bootstrap/crossplane/Chart.yaml                        [Crossplane v2.0.2]
bootstrap/eks-bootstrap/values/crossplane.yaml         [Feature flags]
platform/functions/function-patch-and-transform.yaml   [NEW]
bootstrap/eks-bootstrap/providers/upjet-aws/provider.yaml [v2.1.1]
bootstrap/eks-bootstrap/providers/aws/provider.yaml    [Docs]
platform/providers/upjet-aws-eks.yaml                  [v2.1.1]
docs/CROSSPLANE-V2-MIGRATION-VERIFICATION.md           [NEW]
docs/CROSSPLANE-V2-MIGRATION-SUMMARY.md                [NEW]
```

---

**Total Time**: ~45 minutes (excluding ArgoCD sync wait time)
**Prepared**: 2025-11-04
**Status**: ✅ Ready for Production
