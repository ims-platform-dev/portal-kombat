# IAM Permissions for Crossplane

## 🎯 Quick Start

### For Testing (Fast, but not secure)

```bash
./QUICK-FIX.sh
```

This attaches `AdministratorAccess` to the role. **Only for testing!**

### For Production (Secure, recommended)

```bash
# 1. Create the custom policy
aws iam create-policy \
  --policy-name CrossplaneProviderPolicy \
  --policy-document file://crossplane-provider-policy.json

# 2. Attach to role (replace ACCOUNT_ID)
aws iam attach-role-policy \
  --role-name crossplane-sa-role \
  --policy-arn arn:aws:iam::654654563406:policy/CrossplaneProviderPolicy

# 3. Restart provider
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws
```

## 📁 Files

| File | Purpose |
|------|---------|
| `SETUP-INSTRUCTIONS.md` | Complete step-by-step guide |
| `QUICK-FIX.sh` | Automated script for testing |
| `crossplane-provider-policy.json` | Production-ready IAM policy |

## 🔍 What's the Problem?

The crossplane AWS provider is getting "forbidden" errors because the IAM role doesn't have permissions to manage AWS resources.

**Current Setup:**
- Role: `arn:aws:iam::654654563406:role/crossplane-sa-role`
- Problem: No policies attached (or insufficient permissions)
- Impact: Can't create VPCs, EKS clusters, S3 buckets, etc.

## 🔧 Solution Options

### Option 1: Testing (AdministratorAccess)

**Pros:**
- Fast (1 minute)
- Works for everything
- Good for learning

**Cons:**
- ⚠️ Full AWS access (security risk)
- Not production-ready

**Use when:**
- Testing crossplane
- Learning how it works
- Development environment

### Option 2: Production (Custom Policy)

**Pros:**
- ✅ Least privilege
- ✅ Security best practice
- ✅ Audit-friendly

**Cons:**
- Requires policy creation
- May need adjustments

**Use when:**
- Production deployments
- Security requirements
- Team/organizational use

## ✅ Verification

After fixing permissions:

```bash
# 1. Check logs (should be no "forbidden" errors)
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=50

# 2. Test with S3 bucket
kubectl apply -f ../examples/crossplane/01-s3-bucket.yaml
kubectl get bucket -w

# Should show READY=True within 30 seconds

# 3. Clean up test
kubectl delete -f ../examples/crossplane/01-s3-bucket.yaml
```

## 🎓 What Permissions Are Granted?

The `crossplane-provider-policy.json` includes:

### Core (Required for EKS)
- ✅ **EC2** - VPC, Subnets, Security Groups, Gateways
- ✅ **EKS** - Cluster and Node Group management
- ✅ **IAM** - Roles and policies (required for EKS)

### Optional (Can be removed)
- **S3** - Bucket management
- **RDS** - Database management
- **CloudWatch** - Log groups
- **Auto Scaling** - ASG management
- **ELB** - Load balancer management

## 🔒 Security Best Practices

### For Development
1. Use `AdministratorAccess` for quick testing
2. Remove after testing
3. Switch to custom policy before production

### For Production
1. Use the custom policy from `crossplane-provider-policy.json`
2. Remove unused service permissions
3. Add resource restrictions
4. Enable CloudTrail logging
5. Review permissions regularly

### Advanced: Add Conditions

Limit to specific regions:

```json
"Condition": {
  "StringEquals": {
    "aws:RequestedRegion": ["us-east-2"]
  }
}
```

Require tags:

```json
"Condition": {
  "StringEquals": {
    "aws:RequestTag/ManagedBy": "Crossplane"
  }
}
```

## 🚨 Troubleshooting

### Still seeing "forbidden" errors?

```bash
# 1. Verify policy is attached
aws iam list-attached-role-policies --role-name crossplane-sa-role

# 2. Check pod has the role annotation
kubectl get pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws -o yaml | grep role-arn

# 3. Restart the pod
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws

# 4. Check logs again
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=50
```

### Need more permissions?

If you see errors for specific AWS services:

1. Find the AWS action that failed (in logs)
2. Add it to `crossplane-provider-policy.json`
3. Update the policy:
   ```bash
   aws iam create-policy-version \
     --policy-arn arn:aws:iam::654654563406:policy/CrossplaneProviderPolicy \
     --policy-document file://crossplane-provider-policy.json \
     --set-as-default
   ```
4. Restart the provider pod

## 📚 Next Steps

After fixing permissions:

1. ✅ Test with S3 bucket: `kubectl apply -f ../examples/crossplane/01-s3-bucket.yaml`
2. 📖 Read the walkthrough: `cat ../examples/crossplane/WALKTHROUGH.md`
3. 🚀 Try deploying an EKS cluster (but read the walkthrough first!)

## 🔗 Resources

- [Full Instructions](./SETUP-INSTRUCTIONS.md)
- [Crossplane Examples](../examples/crossplane/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
