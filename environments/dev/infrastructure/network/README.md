# Network Infrastructure Claims

This directory contains VPC network claims for the dev environment.

## Cross-Account Deployment

To deploy VPCs in different AWS accounts, simply change the `providerConfig` parameter:

### Platform Account (Default)
```yaml
spec:
  parameters:
    providerConfig: default  # Uses IRSA directly, no role chaining
```

### Dev Account
```yaml
spec:
  parameters:
    providerConfig: dev-account  # See infra-definitions/shared/configs/provider-configs/
```

### Staging Account
```yaml
spec:
  parameters:
    providerConfig: staging-account
```

### Production Account
```yaml
spec:
  parameters:
    providerConfig: prod-account
```

## Examples

### Create VPC in Dev Account

```bash
# Copy and customize the example
cp dev-shared-vpc.yaml my-app-vpc.yaml

# Edit to use dev account
vim my-app-vpc.yaml
# Change: providerConfig: dev-account

# Commit and push - ArgoCD deploys automatically
git add my-app-vpc.yaml
git commit -m "Add VPC for my-app in dev account"
git push
```

### Verify Deployment

```bash
# Check claim status
kubectl get vpcnetwork my-app-vpc

# Check AWS resources created
kubectl describe vpcnetwork my-app-vpc

# View connection secret
kubectl get secret my-app-vpc-connection -n crossplane-system
```

## Required Setup

Before deploying cross-account resources, ensure:

1. Provider configs are deployed: `kubectl get providerconfigs`
2. IAM trust relationships are configured (see `infra-definitions/shared/configs/provider-configs/CROSS-ACCOUNT-SETUP.md`)
3. Account IDs are updated in provider config files
