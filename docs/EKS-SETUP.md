# EKS Cluster Setup with Crossplane

## Overview

You can now create EKS clusters declaratively using the platform XRD API.

## Components Installed

✅ **EKS Provider**: `provider-upjet-aws-eks` (v1.6.0)
✅ **XRD**: `xeksclusters.aws.plt.intelerad.io`
✅ **Composition**: `ekscluster-standard`

## Prerequisites

Before creating an EKS cluster, you need:

1. **VPC and Subnets**: EKS requires a VPC with at least 2 subnets in different AZs
2. **IAM Permissions**: Crossplane service account needs EKS permissions (already configured via IRSA)

## Option 1: Use Existing VPC

If you have an existing VPC, get the subnet IDs:

```bash
# Get VPC ID
aws ec2 describe-vpcs --region us-east-2

# Get subnet IDs for your VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --region us-east-2 \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table
```

Then update the composition to use your subnet IDs:

```bash
# Edit the composition
kubectl edit composition ekscluster-standard

# Find the vpcConfig section and add your subnet IDs:
vpcConfig:
  - endpointPrivateAccess: true
    endpointPublicAccess: true
    subnetIds:
      - "subnet-xxxxx"
      - "subnet-yyyyy"
```

## Option 2: Create VPC with Crossplane (TODO)

A full VPC+Subnet composition needs to be created. This would include:
- VPC
- Internet Gateway
- NAT Gateways
- Public and Private Subnets
- Route Tables
- Security Groups

## Creating an EKS Cluster

Once you have subnet IDs configured, create a claim:

```yaml
# environments/dev/infrastructure/compute/my-eks-cluster.yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EKSCluster
metadata:
  name: my-app-cluster
  namespace: default
spec:
  parameters:
    clusterName: portal-kombat-dev
    region: us-east-2
    version: "1.28"
    environment: dev
    nodeGroupConfig:
      instanceTypes: ["t3.medium"]
      desiredSize: 2
      minSize: 1
      maxSize: 4
  compositionSelector:
    matchLabels:
      cluster-type: standard
  writeConnectionSecretToRef:
    name: my-app-cluster-connection
```

Apply it:

```bash
kubectl apply -f environments/dev/infrastructure/compute/my-eks-cluster.yaml
```

## What Gets Created

When you create an EKS cluster claim, Crossplane creates:

1. **EKS Cluster** - The control plane
2. **IAM Role** - For the EKS cluster
3. **Role Policy Attachments** - Required EKS policies

## Checking Status

```bash
# Check cluster claim
kubectl get ekscluster -n default

# Check composite resource
kubectl get xekscluster

# Check actual EKS cluster resource
kubectl get cluster.eks.aws.upbound.io

# Check IAM roles
kubectl get role.iam.aws.upbound.io
```

## Connection Info

The cluster connection details (kubeconfig) will be stored in a Kubernetes secret:

```bash
kubectl get secret my-app-cluster-connection -n default -o yaml
```

## Next Steps

To make this production-ready, you need to:

1. ☐ Create a VPC Composition (or use existing VPC)
2. ☐ Add NodeGroup to the composition
3. ☐ Add Security Groups
4. ☐ Configure IRSA for workloads
5. ☐ Set up cluster autoscaler
6. ☐ Configure monitoring/logging

## Cost Warning

⚠️ **EKS clusters cost ~$0.10/hour ($73/month) for the control plane alone, plus EC2 node costs!**

Make sure to delete test clusters when not in use:

```bash
kubectl delete ekscluster my-app-cluster -n default
```

## Troubleshooting

### Provider not installed
```bash
kubectl get provider.pkg.crossplane.io provider-upjet-aws-eks
# Should show INSTALLED=True, HEALTHY=True
```

### XRD not available
```bash
kubectl get xrd xeksclusters.aws.plt.intelerad.io
# Should show ESTABLISHED=True, OFFERED=True
```

### Cluster not creating
```bash
# Check composite resource events
kubectl describe xekscluster <name>

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-eks
```

## References

- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Crossplane AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-aws-eks/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
