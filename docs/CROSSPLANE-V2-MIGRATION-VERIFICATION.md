# Crossplane v2.0 Migration Verification Guide

This document provides step-by-step verification procedures after migrating Portal Kombat to Crossplane v2.0.2.

## Pre-Migration Checklist

Before applying the migration changes:

```bash
# 1. Backup current Crossplane configuration
kubectl get providers -o yaml > backup-providers.yaml
kubectl get xrd -o yaml > backup-xrds.yaml
kubectl get compositions -o yaml > backup-compositions.yaml

# 2. Check current Crossplane version
kubectl get pods -n crossplane-system -o jsonpath='{.items[0].spec.containers[0].image}'
# Should show: crossplane/crossplane:v1.10.1

# 3. Document existing resources
kubectl get managed -o wide > backup-managed-resources.txt
```

## Migration Changes Summary

### Files Modified
1. `bootstrap/crossplane/Chart.yaml` - Crossplane core v1.10.1 → v2.0.2
2. `bootstrap/eks-bootstrap/values/crossplane.yaml` - Feature flags cleanup
3. `platform/functions/function-patch-and-transform.yaml` - NEW function installation
4. `bootstrap/eks-bootstrap/providers/upjet-aws/provider.yaml` - Provider v2.1.1
5. `bootstrap/eks-bootstrap/providers/aws/provider.yaml` - Documentation update
6. `platform/providers/upjet-aws-eks.yaml` - Provider v1.6.0 → v2.1.1

## Post-Migration Verification Steps

### Step 1: Verify Crossplane Core Upgrade

```bash
# Check Crossplane pod is running v2.0.2
kubectl get pods -n crossplane-system -l app=crossplane -o jsonpath='{.items[0].spec.containers[0].image}'
# Expected: crossplane/crossplane:v2.0.2

# Check pod status
kubectl get pods -n crossplane-system
# All pods should be Running

# Check Crossplane logs for errors
kubectl logs -n crossplane-system -l app=crossplane --tail=100
# Should show no errors, look for "Crossplane started successfully"
```

**Success Criteria**:
✅ Crossplane pod running v2.0.2
✅ All pods in Running state
✅ No errors in logs

---

### Step 2: Verify Composition Functions Installed

```bash
# List installed functions
kubectl get functions
# Expected output:
# NAME                           INSTALLED   HEALTHY   PACKAGE                                                              AGE
# function-patch-and-transform   True        True      xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform   1m

# Check function pod status
kubectl get pods -n crossplane-system -l pkg.crossplane.io/function=function-patch-and-transform
# Should show Running pod

# Verify function revision
kubectl get functionrevisions
# Should show active revision for function-patch-and-transform
```

**Success Criteria**:
✅ Function shows INSTALLED=True, HEALTHY=True
✅ Function pod in Running state
✅ Function revision is Active

---

### Step 3: Verify Provider Upgrades

```bash
# List all providers
kubectl get providers
# Expected providers with INSTALLED=True, HEALTHY=True:
# - provider-upjet-aws-eks (v2.1.1)
# - Additional family providers if configured

# Check provider versions
kubectl get providers -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.currentRevision}{"\n"}{end}'

# Verify provider pods are running
kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider
# All provider pods should be Running

# Check provider logs for any errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-eks --tail=50
```

**Success Criteria**:
✅ All providers show INSTALLED=True, HEALTHY=True
✅ Provider versions updated to v2.1.1
✅ Provider pods in Running state
✅ No authentication or permission errors in logs

---

### Step 4: Verify XRDs and Compositions

```bash
# List XRDs
kubectl get xrd
# Expected output:
# NAME                                 ESTABLISHED   OFFERED   AGE
# xobjectstorages.aws.plt.intelerad.io True         True      <time>
# xeksclusters.aws.plt.intelerad.io    True         True      <time>
# xec2instances.aws.plt.intelerad.io   True         True      <time>

# List compositions
kubectl get compositions
# Expected output:
# NAME                    XR-KIND          XR-APIVERSION                   AGE
# objectstorage-private   XObjectStorage   aws.plt.intelerad.io/v1alpha1   <time>
# ekscluster-standard     XEKSCluster      aws.plt.intelerad.io/v1alpha1   <time>
# ec2-standard            XEC2Instance     aws.plt.intelerad.io/v1alpha1   <time>

# Verify composition references functions correctly
kubectl get composition objectstorage-private -o yaml | grep -A 5 "functionRef"
# Should show: name: function-patch-and-transform
```

**Success Criteria**:
✅ All XRDs show ESTABLISHED=True, OFFERED=True
✅ All compositions listed
✅ Compositions correctly reference function-patch-and-transform

---

### Step 5: Test Resource Creation

Create a test S3 bucket claim to verify end-to-end functionality:

```bash
# Create test claim
cat <<EOF | kubectl apply -f -
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: ObjectStorage
metadata:
  name: crossplane-v2-test-bucket
  namespace: default
spec:
  parameters:
    bucketName: portal-kombat-dev-v2-test-$(date +%s)
    region: us-east-2
    versioning: true
    encryption: AES256
    environment: dev
EOF

# Watch claim status (Ctrl+C to exit)
kubectl get objectstorage crossplane-v2-test-bucket -w

# Check claim is Ready
kubectl get objectstorage crossplane-v2-test-bucket
# STATUS should show Ready=True after ~2-3 minutes

# Verify managed resources were created
kubectl get bucket | grep crossplane-v2-test
kubectl get bucketversioning | grep crossplane-v2-test
kubectl get bucketserversideencryptionconfiguration | grep crossplane-v2-test

# Check AWS console to verify bucket exists (optional)

# Cleanup test resources
kubectl delete objectstorage crossplane-v2-test-bucket
```

**Success Criteria**:
✅ Claim reaches Ready=True status
✅ All managed resources (Bucket, BucketVersioning, etc.) created
✅ Resources successfully deleted during cleanup

---

### Step 6: Verify Existing Resources Unaffected

```bash
# Check existing managed resources are still healthy
kubectl get managed
# All existing resources should maintain their Ready status

# Verify no unexpected deletions or updates
kubectl get events -n crossplane-system --sort-by='.lastTimestamp' | tail -20
# Should show normal reconciliation events, no unexpected changes

# Compare with pre-migration backup
diff backup-managed-resources.txt <(kubectl get managed -o wide)
# Should show no unexpected differences
```

**Success Criteria**:
✅ All existing resources remain Ready
✅ No unexpected resource deletions or recreations
✅ Normal reconciliation events only

---

## Troubleshooting Common Issues

### Issue: Crossplane Pod CrashLoopBackOff

**Symptoms**: Crossplane pod repeatedly crashes after upgrade

**Diagnosis**:
```bash
kubectl logs -n crossplane-system -l app=crossplane --previous
kubectl describe pod -n crossplane-system -l app=crossplane
```

**Solutions**:
1. Check resource limits - v2.0 may need more memory
2. Verify RBAC permissions are correct
3. Check for conflicting CRDs from older versions

---

### Issue: Function Not Installing

**Symptoms**: Function shows INSTALLED=False or HEALTHY=False

**Diagnosis**:
```bash
kubectl describe function function-patch-and-transform
kubectl get events -n crossplane-system --field-selector involvedObject.name=function-patch-and-transform
```

**Solutions**:
1. Verify network connectivity to package registry
2. Check image pull secrets if using private registry
3. Verify function package exists: `xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.6.0`

---

### Issue: Provider Authentication Errors

**Symptoms**: Provider shows HEALTHY=False, logs show AWS authentication errors

**Diagnosis**:
```bash
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-eks
kubectl describe providerconfig default
```

**Solutions**:
1. Verify IRSA role ARN in `shared/configs/provider-configs/aws-upbound-runtime-config.yaml`
2. Check IAM role trust relationship allows EKS service account
3. Verify IAM role has required AWS permissions
4. Restart provider pod: `kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-eks`

---

### Issue: Compositions Not Working

**Symptoms**: Claims stuck in "Creating" state, composed resources not created

**Diagnosis**:
```bash
kubectl describe objectstorage <claim-name>
kubectl get events --field-selector involvedObject.name=<claim-name>
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-patch-and-transform
```

**Solutions**:
1. Verify function is installed and healthy (Step 2)
2. Check composition references correct function name
3. Verify XRD schema matches claim spec
4. Check provider has permissions for required AWS resources

---

## Rollback Procedure

If critical issues occur and rollback is necessary:

```bash
# 1. Rollback Crossplane core
helm rollback crossplane -n crossplane-system

# 2. Restore previous provider versions
kubectl apply -f backup-providers.yaml

# 3. Remove function if causing issues
kubectl delete function function-patch-and-transform

# 4. Verify resources are stable
kubectl get managed
kubectl get providers
```

**Note**: Rollback should preserve existing managed resources due to backward compatibility.

---

## Success Confirmation

Migration is successful when ALL of the following are true:

- ✅ Crossplane core running v2.0.2
- ✅ All providers showing INSTALLED=True, HEALTHY=True
- ✅ Function installed and healthy
- ✅ All XRDs ESTABLISHED and OFFERED
- ✅ All compositions listed and functional
- ✅ Test resource claim reaches Ready state
- ✅ Existing resources remain unaffected
- ✅ No errors in Crossplane or provider logs

---

## Next Steps After Successful Migration

1. **Monitor for 24-48 hours**: Watch for any delayed issues or edge cases
2. **Test all claim types**: Create test claims for EKS, EC2, S3, etc.
3. **Update documentation**: Document any environment-specific findings
4. **Plan provider family migration**: Consider migrating from monolithic providers to family providers
5. **Explore v2.0 features**: Consider adopting namespaced resources for multi-tenancy

---

## Additional Resources

- [Crossplane v2.0 Upgrade Guide](https://docs.crossplane.io/latest/guides/upgrade-to-crossplane-v2/)
- [Composition Functions Documentation](https://docs.crossplane.io/latest/concepts/composition-functions/)
- [Upbound Provider Marketplace](https://marketplace.upbound.io/)
- [Portal Kombat Architecture](./ARCHITECTURE.md)
- [Crossplane IRSA Setup](./CROSSPLANE-IRSA-SETUP.md)

---

**Document Version**: 1.0
**Last Updated**: Migration to v2.0.2
**Migration Date**: $(date +%Y-%m-%d)
