# Cross-Account Resource Provisioning with Crossplane

This guide demonstrates how to provision AWS resources in different AWS accounts using Crossplane's IAM role chaining feature.

## Overview

Cross-account resource provisioning allows you to:
- Create resources in production AWS accounts from a management cluster
- Separate blast radius by provisioning in different accounts
- Implement security boundaries between environments
- Use centralized Crossplane deployment for multi-account infrastructure

## Architecture

### IAM Role Chain

The platform uses IAM role chaining to assume roles across AWS accounts:

```
Crossplane Pod (Account 654654563406)
  └─> IRSA Role: raiden-control-plane-upjet-aws-*
       └─> Assume: cross_account_management (Account 873031875931)
            └─> Assume: cross_account_admin (Account 637423399955)
                 └─> Create AWS Resources
```

**Key Concepts:**
- **IRSA (IAM Roles for Service Accounts)**: Kubernetes service account assumes first IAM role
- **assumeRoleChain**: Sequential role assumptions to reach target account
- **Trust Relationships**: Each role must trust the previous role in the chain

## Example: Cross-Account S3 Bucket

### 1. Provider Configuration

Location: `shared/configs/provider-configs/platform-prod.yaml`

```yaml
---
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: platform-prod-account
spec:
  credentials:
    source: IRSA  # Use IAM Role for Service Accounts
  assumeRoleChain:
    # First hop: Management account
    - roleARN: arn:aws:iam::873031875931:role/cross_account_management
    # Second hop: Production account
    - roleARN: arn:aws:iam::637423399955:role/cross_account_admin
```

**Deploy the provider config:**
```bash
kubectl apply -f shared/configs/provider-configs/platform-prod.yaml
```

### 2. Infrastructure Claim with Cross-Account Config

Location: `environments/dev/infrastructure/storage/cross-account-bucket.yaml`

```yaml
---
# Example: Cross-account S3 bucket using platform-prod provider config
# This bucket will be created in the production AWS account (637423399955)
# using IAM role chaining through the management account
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: ObjectStorage
metadata:
  name: cross-account-prod-bucket
  namespace: default
spec:
  parameters:
    bucketName: portal-kombat-cross-account-example-prod-12345
    region: us-east-2
    versioning: true
    encryption: AES256
    publicAccess: false
    environment: production
    # IMPORTANT: This tells Crossplane which provider config to use
    # platform-prod-account has assumeRoleChain for cross-account access
    providerConfig: platform-prod-account
```

**Deploy the infrastructure:**
```bash
kubectl apply -f environments/dev/infrastructure/storage/cross-account-bucket.yaml
```

### 3. Verify Resource Creation

```bash
# Check claim status
kubectl get objectstorage cross-account-prod-bucket

# Check composite resource
kubectl get xobjectstorage

# Check managed resources (S3 bucket, versioning, encryption, etc.)
kubectl get bucket,bucketversioning -l crossplane.io/claim-name=cross-account-prod-bucket

# Check provider config being used
kubectl get bucket <bucket-name> -o jsonpath='{.spec.providerConfigRef.name}'
# Should output: platform-prod-account

# Check for errors
kubectl describe bucket <bucket-name>
```

## Setting Up IAM Trust Relationships

For cross-account provisioning to work, you need to configure IAM trust relationships in each AWS account.

### Required Trust Relationships

**1. Management Account (873031875931)**

Role: `cross_account_management`

Trust Policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::654654563406:role/raiden-control-plane-upjet-aws-20251101112825541500000001"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Permissions: Must have permission to `sts:AssumeRole` on `cross_account_admin` role in production account

**2. Production Account (637423399955)**

Role: `cross_account_admin`

Trust Policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::873031875931:role/cross_account_management"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Permissions: Must have permissions to create AWS resources (S3, EC2, EKS, etc.)

**Note**: The IRSA role name `raiden-control-plane-upjet-aws-20251101112825541500000001` may change. Check your actual role:

```bash
# Find the IRSA role being used
kubectl get sa -n crossplane-system -o yaml | grep eks.amazonaws.com/role-arn
```

## Troubleshooting

### Error: AccessDenied - Cannot AssumeRole

**Error Message:**
```
User: arn:aws:sts::654654563406:assumed-role/raiden-control-plane-upjet-aws-*/...
is not authorized to perform: sts:AssumeRole on resource:
arn:aws:iam::873031875931:role/cross_account_management
```

**Cause:** IAM trust relationship not configured

**Fix:**
1. Verify the IRSA role ARN:
   ```bash
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 | grep "assumed-role"
   ```

2. Update trust policy in management account role to allow the IRSA role to assume it

3. Restart provider pods:
   ```bash
   kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3
   ```

### Error: Invalid ProviderConfig

**Error Message:**
```
cannot get referenced ProviderConfig: ProviderConfig.aws.upbound.io "platform-prod-account" not found
```

**Fix:**
```bash
# Verify provider config exists
kubectl get providerconfigs.aws.upbound.io

# If missing, apply it
kubectl apply -f shared/configs/provider-configs/platform-prod.yaml
```

### Error: Unknown Field spec.parameters.providerConfig

**Error Message:**
```
strict decoding error: unknown field "spec.parameters.providerConfig"
```

**Cause:** XRD doesn't define the providerConfig parameter

**Fix:**
```bash
# Update XRD with providerConfig parameter
kubectl apply -f platform/xrds/storage/xrd-s3-bucket.yaml

# Update composition to patch providerConfig
kubectl apply -f platform/compositions/storage/s3-private.yaml

# May need to delete and recreate CRDs
kubectl delete crd objectstorages.aws.plt.intelerad.io xobjectstorages.aws.plt.intelerad.io
kubectl apply -f platform/xrds/storage/xrd-s3-bucket.yaml
```

## How It Works

### 1. XRD Enhancement

The XRD (`xrd-s3-bucket.yaml`) was enhanced to support a `providerConfig` parameter:

```yaml
spec:
  parameters:
    providerConfig:
      type: string
      description: Name of ProviderConfig for cross-account access (optional, defaults to 'default')
      default: default
```

This allows users to specify which provider config to use when creating resources.

### 2. Composition Patching

The composition (`s3-private.yaml`) patches the `providerConfig` parameter to all managed resources:

```yaml
patches:
  - type: FromCompositeFieldPath
    fromFieldPath: spec.parameters.providerConfig
    toFieldPath: spec.providerConfigRef.name
    policy:
      fromFieldPath: Optional
```

This ensures all resources (Bucket, BucketVersioning, BucketEncryption, etc.) use the specified provider config.

### 3. Credential Flow

1. Kubernetes assigns IRSA role to Crossplane provider pod
2. Provider reads `platform-prod-account` ProviderConfig
3. Provider calls `sts:AssumeRole` on first role in chain (management account)
4. Provider calls `sts:AssumeRole` on second role in chain (production account)
5. Provider uses temporary credentials to create AWS resources in production account

## Best Practices

### Security

1. **Least Privilege**: Grant only necessary permissions to each role in the chain
2. **ExternalID**: Consider adding ExternalID to trust policies for additional security
3. **Audit**: Enable CloudTrail in all accounts to audit cross-account access
4. **Rotate**: Regularly rotate role permissions and review access

### Organization

1. **Naming Convention**: Use consistent role names across accounts
   - `cross_account_management` for management account roles
   - `cross_account_admin` for target account roles

2. **Provider Configs**: Create one provider config per target account
   - `platform-prod-account` → Production account
   - `platform-staging-account` → Staging account
   - `platform-dev-account` → Dev account

3. **Environment Separation**: Use different provider configs in different environments
   - `environments/dev/` → Use dev account provider config
   - `environments/staging/` → Use staging account provider config
   - `environments/prod/` → Use prod account provider config

### Testing

1. **Start Simple**: Test with S3 buckets first (low risk)
2. **Verify Permissions**: Use AWS CLI to test role assumption manually
3. **Check Logs**: Monitor Crossplane provider logs for authentication issues
4. **Incremental**: Add one role at a time to the chain and test

## Additional Examples

### EC2 Instance in Production Account

```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EC2Instance
metadata:
  name: prod-web-server
spec:
  parameters:
    instanceType: t3.small
    amiId: ami-083b3f53cbda7e5a4
    subnetId: subnet-xxxxx
    providerConfig: platform-prod-account  # Cross-account
```

### EKS Cluster in Staging Account

```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EKSCluster
metadata:
  name: staging-cluster
spec:
  parameters:
    clusterName: portal-kombat-staging
    version: "1.28"
    providerConfig: platform-staging-account  # Different account
    vpcConfig:
      subnetIds:
        - subnet-aaaaa
        - subnet-bbbbb
```

## References

- [AWS IAM Role Chaining](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_terms-and-concepts.html)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [Crossplane Provider Configs](https://docs.crossplane.io/latest/concepts/providers/#provider-configuration)
- [Upbound AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-family-aws/)
