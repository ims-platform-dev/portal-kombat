# Terraform Migration Guide - GitOps Refactor

## Overview

This guide helps you safely apply the Terraform refactor that moves provider management from Terraform to ArgoCD (full GitOps).

## What Will Happen

### ✅ Safe Operations (32 resources destroyed, 3 created)

**Terraform will:**
1. **Delete** 15 AWS provider packages (s3, ec2, eks, rds, etc.)
2. **Delete** Kubernetes and Helm providers
3. **Delete** old runtime configs and provider configs
4. **Create** new unified IRSA role for all Crossplane providers
5. **Replace** old `upjet-aws-` role with new `crossplane-` role

**ArgoCD will immediately recreate:**
- All 15 AWS providers from `infra-definitions/providers/`
- Runtime configs from `infra-definitions/shared/configs/provider-configs/`
- Provider configs (default, management, platform-prod)

**Result**: Seamless handoff from Terraform → ArgoCD with no downtime

---

## Pre-Migration Checklist

### 1. Verify ArgoCD is Healthy

```bash
kubectl get applications -n argocd
# Should show all apps as Synced and Healthy
```

### 2. Verify Current Providers are Working

```bash
kubectl get providers
# All providers should show HEALTHY and INSTALLED=True

kubectl get providerconfigs
# Should show: default, management-account, platform-prod-account
```

### 3. Check Existing Infrastructure

```bash
kubectl get managed
# Should show any existing S3 buckets, RDS instances, etc.
# These will NOT be affected - only provider management changes
```

### 4. Backup Current State (Optional but Recommended)

```bash
# Export current provider state
kubectl get providers -o yaml > /tmp/providers-backup.yaml
kubectl get providerconfigs -A -o yaml > /tmp/providerconfigs-backup.yaml

# Terraform state backup (automatic, but verify)
terraform show > /tmp/terraform-state-backup.txt
```

---

## Migration Steps

### Step 1: Clean Variables (Already Done ✅)

Updated `raiden.tfvars` to remove deprecated provider enable flags.

### Step 2: Run Terraform Plan

```bash
cd bootstrap/terraform/eks-bootstrap
terraform plan -var-file=raiden.tfvars -out=migration.tfplan
```

**Expected output**:
```
Plan: 3 to add, 1 to change, 32 to destroy.

Changes to Outputs:
  + crossplane_irsa_role_arn     = (known after apply)
  + crossplane_irsa_role_name    = (known after apply)
```

**Verify**:
- ✅ 32 resources being destroyed (providers, configs, old IRSA role)
- ✅ 3 resources being added (new unified IRSA role + attachments)
- ✅ 1 change (EnvironmentConfig update)
- ✅ New outputs for IRSA role ARN

### Step 3: Apply Terraform Changes

```bash
terraform apply migration.tfplan
```

**What happens during apply**:
1. **Phase 1** (30-60 seconds): Terraform destroys old provider resources
2. **Phase 2** (immediate): ArgoCD detects Git state and starts redeploying
3. **Phase 3** (2-3 minutes): Providers reinstall and become HEALTHY

**Timeline**:
```
T+0s:    Terraform starts destroying old providers
T+30s:   Old providers deleted
T+35s:   New IRSA role created
T+40s:   ArgoCD syncs and starts deploying providers from Git
T+120s:  All providers INSTALLED
T+180s:  All providers HEALTHY
```

### Step 4: Monitor ArgoCD Deployment

Open a new terminal and watch ArgoCD applications:

```bash
watch -n 2 'kubectl get applications -n argocd | grep crossplane'
```

Expected progression:
```
NAME                        SYNC STATUS   HEALTH STATUS
dev-crossplane-providers    OutOfSync     Progressing
dev-crossplane-providers    Synced        Progressing
dev-crossplane-providers    Synced        Healthy
```

### Step 5: Verify Providers Reinstall

```bash
# Watch providers come back online
watch -n 5 'kubectl get providers'

# Should see all 15 providers return to HEALTHY status:
# provider-upjet-aws-s3
# provider-upjet-aws-ec2
# provider-upjet-aws-eks
# ... etc
```

### Step 6: Check Provider Pods

```bash
kubectl get pods -n crossplane-system | grep provider

# Should see pods for all providers in Running state:
# provider-upjet-aws-s3-xxx     1/1  Running
# provider-upjet-aws-ec2-xxx    1/1  Running
# etc.
```

### Step 7: Verify IRSA Role is Working

```bash
# Get new IRSA role ARN
terraform output crossplane_irsa_role_arn

# Verify it matches what's in the runtime config
kubectl get deploymentruntimeconfig aws-upbound-runtime-config -o yaml | grep role-arn
```

**Expected**:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::654654563406:role/raiden-control-plane-crossplane-XXXXXXXXXX
```

### Step 8: Test Infrastructure Provisioning

Create a test S3 bucket to verify everything works:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: test-migration-$(date +%s)
spec:
  forProvider:
    region: us-east-2
  providerConfigRef:
    name: default
EOF

# Watch bucket creation
kubectl get buckets -w
```

**Expected**: Bucket should provision successfully and show `READY: True`

### Step 9: Update Runtime Config with New IRSA Role ARN

```bash
# Get the new IRSA role ARN
NEW_ROLE_ARN=$(terraform output -raw crossplane_irsa_role_arn)
echo "New IRSA Role ARN: $NEW_ROLE_ARN"

# Update the runtime config in Git
# Edit: infra-definitions/shared/configs/provider-configs/aws-upbound-runtime-config.yaml
# Replace the old role ARN with the new one

# Commit and push
git add infra-definitions/shared/configs/provider-configs/aws-upbound-runtime-config.yaml
git commit -m "chore: update runtime config with new IRSA role ARN from Terraform"
git push

# ArgoCD will sync automatically and update provider service accounts
```

### Step 10: Verify Migration Success

```bash
# All providers should be healthy
kubectl get providers
# STATUS: All should show HEALTHY=True, INSTALLED=True

# ArgoCD applications should be synced
kubectl get applications -n argocd
# STATUS: All should show Synced and Healthy

# Existing infrastructure should be unchanged
kubectl get managed
# STATUS: All existing resources should remain READY=True

# New IRSA role should be in use
kubectl get sa -n crossplane-system -o yaml | grep role-arn
# Should show new role ARN: raiden-control-plane-crossplane-XXXXX
```

---

## Rollback Plan (If Needed)

If something goes wrong, you can rollback:

### Option 1: Rollback Terraform (Quick)

```bash
# Revert Git changes
git revert <cleanup-commit-hash>

# Re-apply old Terraform
cd bootstrap/terraform/eks-bootstrap
terraform plan -var-file=raiden.tfvars
terraform apply
```

This will recreate the old provider deployment structure.

### Option 2: Manual Provider Recovery

If providers don't come back automatically:

```bash
# Force ArgoCD sync
kubectl patch application dev-crossplane-providers -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Or manually apply provider packages
kubectl apply -f infra-definitions/providers/
```

### Option 3: Restore from Backup

```bash
# Restore provider state
kubectl apply -f /tmp/providers-backup.yaml
kubectl apply -f /tmp/providerconfigs-backup.yaml
```

---

## Troubleshooting

### Issue 1: Providers Stuck in Installing

**Symptom**: Providers show `INSTALLED=False` for >5 minutes

**Solution**:
```bash
# Check provider pod logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-s3

# Common cause: IRSA role misconfiguration
# Verify service account annotations
kubectl get sa -n crossplane-system -o yaml | grep role-arn

# Should match: terraform output crossplane_irsa_role_arn
```

### Issue 2: ArgoCD Not Syncing

**Symptom**: ArgoCD applications stuck in OutOfSync

**Solution**:
```bash
# Force sync
kubectl patch application dev-crossplane-providers -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Check ArgoCD logs
kubectl logs -n argocd deployment/argocd-application-controller | grep crossplane
```

### Issue 3: Existing Infrastructure Affected

**Symptom**: Existing S3 buckets or RDS instances show errors

**Cause**: Provider version mismatch or IRSA permissions

**Solution**:
```bash
# Check managed resource status
kubectl describe bucket <bucket-name>

# Check provider credentials
kubectl get providerconfigs
kubectl describe providerconfig default

# Verify IAM permissions
aws sts get-caller-identity --role-arn $(terraform output -raw crossplane_irsa_role_arn)
```

### Issue 4: Old IRSA Role Still in Use

**Symptom**: Runtime config still references old role ARN

**Solution**:
```bash
# Get current runtime config
kubectl get deploymentruntimeconfig aws-upbound-runtime-config -o yaml

# Update with new role ARN
# Edit infra-definitions/shared/configs/provider-configs/aws-upbound-runtime-config.yaml
# Commit and push to trigger ArgoCD sync
```

---

## Post-Migration Verification

### Checklist

- [ ] All 15 AWS providers show HEALTHY=True
- [ ] ArgoCD applications show Synced and Healthy
- [ ] New IRSA role ARN is in use (`terraform output crossplane_irsa_role_arn`)
- [ ] Runtime config updated with new role ARN
- [ ] Existing infrastructure remains READY=True (no disruption)
- [ ] Test bucket provisions successfully
- [ ] Provider pods are Running in crossplane-system namespace
- [ ] No errors in provider logs

### Commands Summary

```bash
# Quick health check
kubectl get providers
kubectl get providerconfigs
kubectl get applications -n argocd | grep crossplane
kubectl get pods -n crossplane-system | grep provider
kubectl get managed
terraform output crossplane_irsa_role_arn
```

---

## Expected Downtime

**Zero downtime for existing infrastructure!**

- Existing managed resources (S3 buckets, RDS, etc.) are **not affected**
- Only provider management changes (how providers are deployed)
- Brief transition period (~2-3 minutes) where new providers install
- During transition, existing resources continue functioning normally
- New resource creation may be delayed during provider reinstall

---

## Success Criteria

Migration is successful when:

1. ✅ All 15 AWS providers return to HEALTHY status
2. ✅ ArgoCD manages providers (shown in `dev-crossplane-providers` app)
3. ✅ New unified IRSA role is in use
4. ✅ Existing infrastructure remains functional
5. ✅ New infrastructure can be provisioned
6. ✅ No Terraform resources for providers (only IRSA role)

---

## Next Steps After Migration

1. **Update documentation** pointing to GitOps workflow
2. **Provider version updates** now done via Git commits to `infra-definitions/providers/`
3. **Runtime config changes** done via Git commits to `infra-definitions/shared/configs/`
4. **Monitor** provider health for 24 hours to ensure stability

---

## Questions?

If you encounter issues not covered here:

1. Check provider pod logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-s3`
2. Check ArgoCD application status: `kubectl describe application dev-crossplane-providers -n argocd`
3. Verify IRSA permissions: Check IAM role has AdministratorAccess policy attached
4. Review `docs/CLEANUP-2025-01-05.md` for architecture details
