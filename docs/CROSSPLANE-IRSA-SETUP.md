# Crossplane IRSA (IAM Roles for Service Accounts) Setup Guide

This guide explains how to set up IRSA for Crossplane providers to securely access AWS resources without storing credentials.

## Overview

**IRSA** allows Kubernetes pods to assume IAM roles using OIDC (OpenID Connect) federation. Instead of storing AWS credentials in secrets, pods use short-lived tokens that are automatically refreshed.

### Architecture

```
Crossplane Provider Pod
    ↓ (uses service account with IRSA annotation)
EKS OIDC Provider
    ↓ (federates identity)
IAM Role (with trust policy)
    ↓ (has permissions)
AWS Resources (S3, EC2, RDS, etc.)
```

## Prerequisites

- EKS cluster with OIDC provider enabled
- Terraform or AWS CLI access to create IAM roles
- ArgoCD installed and managing Crossplane

## Step 1: Create IAM Role with Terraform

The IAM role is created via Terraform because it requires AWS API access.

### 1.1 Apply Terraform Configuration

```bash
cd bootstrap/eks-bootstrap

# Initialize Terraform (if not already done)
terraform init

# Review what will be created
terraform plan

# Apply to create the IAM role
terraform apply
```

This creates:
- **IAM Policy**: `crossplane-provider-policy` with permissions for S3, EC2, EKS, IAM, RDS, etc.
- **IAM Role**: `CLUSTER_NAME-crossplane-upbound-*` with OIDC trust policy
- **Trust Relationship**: Allows service accounts `provider-aws-*` in `crossplane-system` namespace

### 1.2 Get the IAM Role ARN

```bash
# Get the IAM role ARN
terraform output crossplane_upbound_irsa_role_arn

# Example output:
# arn:aws:iam::123456789012:role/my-cluster-crossplane-upbound-20250102123456
```

**Copy this ARN - you'll need it in Step 2.**

## Step 2: Configure DeploymentRuntimeConfig

The DeploymentRuntimeConfig tells Crossplane to annotate provider service accounts with the IAM role ARN.

### 2.1 Update the Runtime Config

Edit: `shared/configs/provider-configs/aws-upbound-runtime-config.yaml`

```yaml
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: aws-upbound-runtime-config
spec:
  serviceAccountTemplate:
    metadata:
      annotations:
        # REPLACE THIS with your actual IAM role ARN from Step 1.2
        eks.amazonaws.com/role-arn: "arn:aws:iam::123456789012:role/my-cluster-crossplane-upbound-20250102123456"
```

### 2.2 Commit and Push

```bash
git add shared/configs/provider-configs/aws-upbound-runtime-config.yaml
git commit -m "Configure Crossplane IRSA with IAM role ARN"
git push
```

ArgoCD will automatically sync and apply this configuration.

## Step 3: Verify IRSA Configuration

### 3.1 Check Provider Pods Have IRSA Annotations

```bash
# Wait for providers to be installed
kubectl wait --for=condition=Healthy provider/provider-aws-s3 --timeout=300s

# Check service account annotations
kubectl get sa -n crossplane-system -o yaml | grep -A 2 "eks.amazonaws.com/role-arn"

# You should see the IAM role ARN in the annotations
```

### 3.2 Check Provider Logs

```bash
# Get provider pod name
kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3

# Check logs - should show successful AWS authentication
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=50
```

Look for messages like:
```
"Successfully configured AWS credentials"
"Reconciling resource"
```

### 3.3 Verify Provider is Healthy

```bash
kubectl get providers

# Expected output:
# NAME                INSTALLED   HEALTHY   PACKAGE                                              AGE
# provider-aws-s3     True        True      xpkg.upbound.io/upbound/provider-aws-s3:v1.7.0      5m
# provider-aws-ec2    True        True      xpkg.upbound.io/upbound/provider-aws-ec2:v1.7.0     5m
# ...
```

### 3.4 Test with a Simple Resource

Create a test S3 bucket to verify IRSA is working:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: test-crossplane-irsa-$(date +%s)
spec:
  forProvider:
    region: us-east-1
  providerConfigRef:
    name: default
EOF
```

Check if it gets created:
```bash
kubectl get buckets -w

# Should show:
# NAME                          READY   SYNCED   EXTERNAL-NAME                 AGE
# test-crossplane-irsa-123456   True    True     test-crossplane-irsa-123456   30s
```

If `READY` is `True`, IRSA is working! 🎉

Clean up:
```bash
kubectl delete bucket test-crossplane-irsa-123456
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Crossplane Provider Pod (provider-aws-s3-xxxx)              │
│                                                              │
│  Service Account: provider-aws-s3-xxxxx                     │
│  Annotation: eks.amazonaws.com/role-arn: arn:aws:iam::...   │
│                                                              │
│  ├─ Pod uses SA token                                       │
│  └─ EKS mutates pod to inject AWS_WEB_IDENTITY_TOKEN_FILE   │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ EKS OIDC Provider                                            │
│  https://oidc.eks.{region}.amazonaws.com/id/{cluster-id}    │
│                                                              │
│  Validates SA token and exchanges for AWS credentials       │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ IAM Role: my-cluster-crossplane-upbound-xxxx                │
│                                                              │
│  Trust Policy: Allows OIDC provider for crossplane-system/* │
│  Permissions: crossplane-provider-policy (S3, EC2, IAM...)  │
└──────────────────────┬───────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ AWS APIs (S3, EC2, RDS, IAM, EKS)                           │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Order with Sync Waves

```
Wave -1: Crossplane Core Installation
    └─ Installs Crossplane controller + CRDs

Wave 0: Platform Apps (Providers)
    └─ Installs AWS provider packages (S3, EC2, EKS, IAM, RDS)
    └─ References: runtimeConfigRef: aws-upbound-runtime-config

Wave 1: Provider Configs
    └─ DeploymentRuntimeConfig (IRSA annotations)
    └─ ProviderConfigs (authentication method: InjectedIdentity)

Wave 2: Infrastructure Claims
    └─ Your actual infrastructure resources (buckets, VPCs, etc.)
```

## Files Created/Modified

### Terraform (IAM Role)
- `bootstrap/eks-bootstrap/crossplane-irsa.tf` - Creates IAM role with OIDC trust policy

### Platform Layer (Providers)
- `platform/providers/aws-provider.yaml` - References runtime config

### Shared Layer (Configs)
- `shared/configs/provider-configs/aws-upbound-runtime-config.yaml` - IRSA annotation
- `shared/configs/provider-configs/aws-upbound-provider-config.yaml` - InjectedIdentity auth

### ArgoCD Apps
- `environments/dev/argocd/crossplane-install.yaml` - Wave -1
- `environments/dev/argocd/platform-apps.yaml` - Wave 0
- `environments/dev/argocd/provider-configs-app.yaml` - Wave 1
- `environments/dev/argocd/root-app.yaml` - Entry point

## Troubleshooting

### Provider not authenticating

**Symptom**: Provider logs show AWS authentication errors

**Check**:
```bash
# 1. Verify service account has annotation
kubectl get sa -n crossplane-system provider-aws-s3-xxxxx -o yaml | grep role-arn

# 2. Check IAM role trust policy
aws iam get-role --role-name my-cluster-crossplane-upbound-xxxxx \
  --query 'Role.AssumeRolePolicyDocument'

# 3. Verify OIDC provider exists
aws iam list-open-id-connect-providers

# 4. Check provider pod environment
kubectl get pod -n crossplane-system provider-aws-s3-xxxxx -o yaml | grep -A 5 AWS_
```

### Resources stuck in "Synced: False"

**Symptom**: Resources don't reconcile, stuck in syncing state

**Check**:
```bash
# Check provider logs for AWS permission errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=100

# Look for errors like:
# "AccessDenied: User: arn:aws:sts::...:assumed-role/... is not authorized to perform: s3:CreateBucket"
```

**Fix**: Update IAM policy in `shared/managed-resources/iam-roles/iam-policies/crossplane-provider-policy.json`

### IRSA annotation not applied

**Symptom**: Service account doesn't have `eks.amazonaws.com/role-arn` annotation

**Check**:
```bash
# 1. Verify DeploymentRuntimeConfig exists
kubectl get deploymentruntimeconfig aws-upbound-runtime-config -o yaml

# 2. Verify providers reference the runtime config
kubectl get provider provider-aws-s3 -o yaml | grep runtimeConfigRef

# 3. Check provider revision status
kubectl get providerrevision
```

**Fix**: Ensure `platform/providers/aws-provider.yaml` has `runtimeConfigRef` and sync ArgoCD.

## Security Best Practices

1. **Least Privilege**: Use minimal IAM permissions needed
   - Review `crossplane-provider-policy.json`
   - Remove unused permissions

2. **Role Session Duration**: Set appropriate session duration
   ```terraform
   max_session_duration = 3600  # 1 hour
   ```

3. **Condition Keys**: Add conditions to IAM trust policy
   ```json
   "Condition": {
     "StringEquals": {
       "oidc.eks.region.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:crossplane-system:provider-aws-*"
     }
   }
   ```

4. **Audit Logging**: Enable CloudTrail for Crossplane IAM role usage

5. **Rotation**: IAM credentials are automatically rotated (no manual rotation needed)

## References

- [EKS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Crossplane Provider Configuration](https://docs.crossplane.io/latest/concepts/providers/)
- [Upbound Provider AWS Docs](https://marketplace.upbound.io/providers/upbound/provider-aws/)

## Next Steps

After IRSA is configured:
1. Create infrastructure resources using Crossplane (S3 buckets, VPCs, etc.)
2. Define XRDs for your platform APIs
3. Create Compositions to bundle resources
4. Deploy infrastructure via ArgoCD GitOps
