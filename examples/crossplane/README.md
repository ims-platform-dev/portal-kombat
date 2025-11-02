# Crossplane Examples

This directory contains examples for deploying infrastructure using Crossplane on your EKS cluster.

## Prerequisites

Before using these examples, ensure:

1. Crossplane is installed in your cluster
2. AWS Provider is installed and healthy
3. ProviderConfig is configured with proper IAM permissions

Check the status:
```bash
kubectl get providers
kubectl get providerconfig.aws.crossplane.io
```

## IAM Permissions

The crossplane providers need IAM permissions to create AWS resources. Currently, the provider is configured to use `InjectedIdentity` with the IAM role:
- `arn:aws:iam::654654563406:role/crossplane-sa-role`

This role needs permissions for the resources you want to create (EC2, EKS, S3, RDS, etc.).

## Examples

### 1. Simple AWS Resources

- **[01-s3-bucket.yaml](./01-s3-bucket.yaml)** - Create a simple S3 bucket
- **[02-vpc.yaml](./02-vpc.yaml)** - Create a VPC with subnets

### 2. EKS Cluster

- **[03-eks-cluster-simple.yaml](./03-eks-cluster-simple.yaml)** - Deploy a basic EKS cluster using AWS provider
- **[04-eks-cluster-custom.yaml](./04-eks-cluster-custom.yaml)** - Deploy EKS using custom composition (requires composition to be installed)

### 3. Advanced Examples

- **[05-rds-database.yaml](./05-rds-database.yaml)** - Deploy an RDS PostgreSQL database
- **[06-complete-app-infrastructure.yaml](./06-complete-app-infrastructure.yaml)** - Full stack with VPC, EKS, RDS, and S3

## Quick Start

### Deploy a Simple S3 Bucket

```bash
kubectl apply -f 01-s3-bucket.yaml

# Check status
kubectl get bucket
kubectl describe bucket my-crossplane-bucket
```

### Deploy an EKS Cluster

```bash
# Option 1: Using AWS provider directly (simpler)
kubectl apply -f 03-eks-cluster-simple.yaml

# Option 2: Using custom composition (requires composition installed)
kubectl apply -f 04-eks-cluster-custom.yaml

# Check status
kubectl get cluster
kubectl describe cluster my-eks-cluster
```

## Troubleshooting

### Check Provider Logs

```bash
# AWS provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws

# All crossplane logs
kubectl logs -n crossplane-system -l app=crossplane
```

### Check Resource Status

```bash
# List all managed resources
kubectl get managed

# Get specific resource details
kubectl describe <resource-type> <resource-name>
```

### Common Issues

1. **"User is forbidden" errors** - The IAM role needs additional permissions
2. **"Resource already exists"** - The resource may exist in AWS already
3. **"Composition not found"** - Install the composition first before creating claims

## Cleaning Up

Delete resources in reverse order:

```bash
# Delete claims/composite resources first
kubectl delete -f 04-eks-cluster-custom.yaml

# Then delete provider resources
kubectl delete -f 01-s3-bucket.yaml

# Verify deletion
kubectl get managed
```

## Additional Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [AWS Provider Reference](https://marketplace.upbound.io/providers/crossplane-contrib/provider-aws/)
- [Composition Guide](https://docs.crossplane.io/latest/concepts/compositions/)
