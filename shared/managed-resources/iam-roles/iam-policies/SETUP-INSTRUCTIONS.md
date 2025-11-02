# Fixing Crossplane IAM Permissions

## Problem

The crossplane AWS provider is getting "forbidden" errors when trying to list AWS resources. This is because the IAM role `crossplane-sa-role` doesn't have sufficient permissions.

## Solution

You need to attach an IAM policy to the role that grants permissions for the AWS resources you want to manage.

## Current Configuration

- **IAM Role**: `arn:aws:iam::654654563406:role/crossplane-sa-role`
- **Used by**: AWS Provider pod in crossplane-system namespace
- **Authentication**: IRSA (IAM Roles for Service Accounts)

## Step-by-Step Fix

### Option 1: Quick Fix (For Testing) - Use Administrator Access

**⚠️ WARNING: This grants full AWS access. Only use for testing!**

```bash
# Set your AWS profile if needed
export AWS_PROFILE=ims-platform-dev

# Attach AdministratorAccess policy to the role
aws iam attach-role-policy \
  --role-name crossplane-sa-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# Verify it's attached
aws iam list-attached-role-policies --role-name crossplane-sa-role
```

**After attaching the policy:**
```bash
# Restart the provider pod to pick up new permissions
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws

# Wait for pod to restart
kubectl get pods -n crossplane-system -w

# Check logs - should no longer show "forbidden" errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=50
```

### Option 2: Production Approach - Use Custom Policy

**This grants only the permissions Crossplane needs.**

#### Step 1: Create the IAM Policy

```bash
# Create the policy from the JSON file
aws iam create-policy \
  --policy-name CrossplaneProviderPolicy \
  --policy-document file://iam-policies/crossplane-provider-policy.json \
  --description "Permissions for Crossplane to manage AWS resources"

# Note the ARN from the output, it will look like:
# arn:aws:iam::654654563406:policy/CrossplaneProviderPolicy
```

#### Step 2: Attach the Policy to the Role

```bash
# Replace with your actual policy ARN
POLICY_ARN="arn:aws:iam::654654563406:policy/CrossplaneProviderPolicy"

aws iam attach-role-policy \
  --role-name crossplane-sa-role \
  --policy-arn $POLICY_ARN

# Verify it's attached
aws iam list-attached-role-policies --role-name crossplane-sa-role
```

#### Step 3: Restart the Provider Pod

```bash
# Restart to pick up new permissions
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws

# Wait for restart
kubectl get pods -n crossplane-system -w
```

### Option 3: Using AWS Console

If you prefer using the AWS Console:

1. **Go to IAM Console**: https://console.aws.amazon.com/iam/
2. **Navigate to Roles**
3. **Search for**: `crossplane-sa-role`
4. **Click the role name**
5. **Click "Add permissions"** → "Attach policies"
6. **For Testing**: Search for and select `AdministratorAccess`
7. **For Production**:
   - First create a new policy:
     - Click "Policies" in left sidebar
     - Click "Create policy"
     - Click "JSON" tab
     - Paste contents from `iam-policies/crossplane-provider-policy.json`
     - Name it: `CrossplaneProviderPolicy`
     - Create policy
   - Then attach to role:
     - Go back to the `crossplane-sa-role`
     - Click "Add permissions" → "Attach policies"
     - Search for `CrossplaneProviderPolicy`
     - Select and attach

## Verification

### Check Role Has Policies

```bash
# List all policies attached to the role
aws iam list-attached-role-policies --role-name crossplane-sa-role

# Should show:
# {
#     "AttachedPolicies": [
#         {
#             "PolicyName": "CrossplaneProviderPolicy",
#             "PolicyArn": "arn:aws:iam::654654563406:policy/CrossplaneProviderPolicy"
#         }
#     ]
# }
```

### Check Provider Logs

```bash
# Check for errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=100

# Should see no "forbidden" or "access denied" errors
# Should see successful API calls
```

### Test with Simple Resource

```bash
# Try creating an S3 bucket
kubectl apply -f examples/crossplane/01-s3-bucket.yaml

# Watch the status
kubectl get bucket -w

# Should change from False to True within 30 seconds
# If you see errors:
kubectl describe bucket my-crossplane-example-bucket

# Clean up
kubectl delete -f examples/crossplane/01-s3-bucket.yaml
```

## What Permissions Are Granted

The `crossplane-provider-policy.json` includes permissions for:

### Core Services (Required)
- **EC2**: VPC, Subnets, Security Groups, Internet Gateways, NAT Gateways, Route Tables
- **EKS**: Create/manage clusters and node groups
- **IAM**: Create/manage roles and policies (needed for EKS)

### Optional Services (Can remove if not needed)
- **S3**: Bucket management
- **RDS**: Database management
- **CloudWatch Logs**: Log groups
- **Auto Scaling**: Auto scaling groups
- **ELB**: Load balancers

### Remove Unused Services

If you don't plan to use certain services, you can remove those sections from the policy:

```bash
# Edit the policy file
vi iam-policies/crossplane-provider-policy.json

# Remove sections you don't need (like RDS, S3, etc.)

# Update the policy (if already created)
aws iam create-policy-version \
  --policy-arn arn:aws:iam::654654563406:policy/CrossplaneProviderPolicy \
  --policy-document file://iam-policies/crossplane-provider-policy.json \
  --set-as-default
```

## Troubleshooting

### Still Getting "Forbidden" Errors

1. **Check the pod picked up the changes**:
   ```bash
   # Verify the pod has the IAM role annotation
   kubectl get pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws -o yaml | grep -A 5 "eks.amazonaws.com/role-arn"

   # Should show: eks.amazonaws.com/role-arn: arn:aws:iam::654654563406:role/crossplane-sa-role
   ```

2. **Check IRSA is configured**:
   ```bash
   # Check if the service account has the annotation
   kubectl get sa -n crossplane-system -o yaml | grep -A 3 "eks.amazonaws.com/role-arn"
   ```

3. **Verify trust relationship**:
   ```bash
   # Check the role's trust policy
   aws iam get-role --role-name crossplane-sa-role --query 'Role.AssumeRolePolicyDocument'

   # Should allow the EKS OIDC provider to assume the role
   ```

4. **Check for specific permission errors**:
   ```bash
   # Get detailed errors
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws | grep -i "denied\|forbidden" | tail -20
   ```

### Permission Errors for Specific Resources

If you see errors like "User is forbidden to perform eks:DescribeCluster", you may need additional permissions:

```bash
# Check what action failed
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws | grep forbidden

# Add the missing permission to the policy
# Edit iam-policies/crossplane-provider-policy.json
# Update the policy as shown above
```

## Security Best Practices

### For Production

1. **Use least privilege**: Only grant permissions for resources you'll actually create
2. **Use conditions**: Add conditions to limit what can be created
3. **Use resource restrictions**: Instead of `"Resource": "*"`, specify ARN patterns
4. **Monitor usage**: Set up CloudTrail to monitor what Crossplane is doing
5. **Rotate regularly**: Consider rotating the role periodically

### Example: Restrict to Specific Regions

Add a condition to limit operations to specific regions:

```json
{
  "Sid": "EC2Permissions",
  "Effect": "Allow",
  "Action": ["ec2:*"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:RequestedRegion": ["us-east-2", "us-west-2"]
    }
  }
}
```

### Example: Require Specific Tags

Require all created resources to have specific tags:

```json
{
  "Sid": "RequireTags",
  "Effect": "Allow",
  "Action": ["ec2:CreateVpc", "eks:CreateCluster"],
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:RequestTag/ManagedBy": "Crossplane"
    }
  }
}
```

## Additional Resources

- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Crossplane AWS Provider Docs](https://marketplace.upbound.io/providers/crossplane-contrib/provider-aws/)

## Quick Reference Commands

```bash
# Check role policies
aws iam list-attached-role-policies --role-name crossplane-sa-role

# Check provider pods
kubectl get pods -n crossplane-system

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=50

# Restart provider
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws

# Test permissions
kubectl apply -f examples/crossplane/01-s3-bucket.yaml
kubectl get bucket -w
kubectl delete -f examples/crossplane/01-s3-bucket.yaml
```
