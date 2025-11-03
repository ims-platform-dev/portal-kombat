# GitOps Workflow: Deploy Infrastructure by Commit Only

## Overview

This repository uses **ArgoCD** for GitOps. Any infrastructure you commit to Git will be automatically deployed to your cluster.

## Architecture

```
Git Push → ArgoCD Detects Changes → Syncs to Cluster → Crossplane Creates AWS Resources
```

## ArgoCD Applications

| App Name | Sync Wave | Watches | Deploys |
|----------|-----------|---------|---------|
| `dev-rbac` | -2 | `shared/configs/rbac/` | Provider RBAC permissions |
| `dev-additional-providers` | -1 | `platform/providers/` | Additional Crossplane providers |
| `dev-platform-crossplane` | 0 | `platform/` (excluding providers) | XRDs, Compositions, Functions |
| `dev-provider-configs` | 1 | `shared/configs/provider-configs/` | ProviderConfigs |
| `dev-infrastructure` | 2 | `environments/dev/infrastructure/` | Infrastructure claims (S3, EKS, etc.) |

**All apps have automated sync enabled** - changes are deployed automatically within 3 minutes!

## Creating an EKS Cluster (GitOps Way)

### Step 1: Prepare Your Cluster Configuration

First, get your VPC subnet IDs:

```bash
aws ec2 describe-subnets --region us-east-2 \
  --query 'Subnets[?MapPublicIpOnLaunch==`true`].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table
```

### Step 2: Update the Composition with Subnet IDs

Edit `platform/compositions/compute/eks-standard.yaml` and add your subnet IDs:

```yaml
vpcConfig:
  - endpointPrivateAccess: true
    endpointPublicAccess: true
    subnetIds:
      - "subnet-abc123"  # Replace with your subnet IDs
      - "subnet-def456"
```

### Step 3: Create Your Cluster Claim

Create a new file:

```bash
# Create your cluster configuration
cat > environments/dev/infrastructure/compute/dev-cluster.yaml << 'EOF'
---
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EKSCluster
metadata:
  name: portal-kombat-dev-cluster
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
    name: portal-kombat-dev-cluster-connection
EOF
```

### Step 4: Commit and Push

```bash
# Stage all changes
git add .

# Commit
git commit -m "Add EKS cluster for dev environment"

# Push to trigger deployment
git push origin main
```

### Step 5: Monitor Deployment

```bash
# Watch ArgoCD sync status
kubectl get applications -n argocd

# Watch for your cluster claim to appear (after ArgoCD syncs)
kubectl get ekscluster -n default -w

# Watch the actual EKS cluster being created
kubectl get cluster.eks.aws.upbound.io -w
```

## Timeline

| Time | What Happens |
|------|--------------|
| 0 min | You push to Git |
| ~3 min | ArgoCD detects changes and syncs |
| ~3 min | Kubernetes resources created (EKSCluster claim) |
| ~5 min | Crossplane starts provisioning AWS resources |
| ~20 min | EKS cluster ready in AWS |

## What Gets Created in AWS

When you commit an EKS cluster claim:

1. **IAM Role** - For EKS cluster service
2. **IAM Policy Attachments** - Required EKS permissions
3. **EKS Control Plane** - The managed Kubernetes cluster
4. (Future) **Node Group** - EC2 instances for workloads

## Viewing Resources

### In Kubernetes:

```bash
# Claims (what you requested)
kubectl get ekscluster -n default

# Composites (Crossplane's internal representation)
kubectl get xekscluster

# Managed Resources (actual AWS resources)
kubectl get cluster.eks.aws.upbound.io
kubectl get role.iam.aws.upbound.io
kubectl get rolepolicyattachment.iam.aws.upbound.io
```

### In AWS Console:

1. Go to EKS Console → Clusters
2. Find cluster named `portal-kombat-dev`
3. View details, node groups, add-ons, etc.

## Modifying a Cluster

Just edit the file and commit:

```bash
# Edit cluster configuration
vim environments/dev/infrastructure/compute/dev-cluster.yaml

# Change desired node count, instance types, etc.

# Commit changes
git add environments/dev/infrastructure/compute/dev-cluster.yaml
git commit -m "Scale cluster to 3 nodes"
git push
```

ArgoCD will sync the changes and Crossplane will update AWS resources.

## Deleting a Cluster

Simply remove the file and commit:

```bash
# Remove cluster file
git rm environments/dev/infrastructure/compute/dev-cluster.yaml

# Commit deletion
git commit -m "Remove dev EKS cluster"
git push
```

ArgoCD will delete the Kubernetes resources, and Crossplane will delete the AWS resources.

⚠️ **Warning**: With `prune: true`, deletion happens automatically! Be careful!

## Creating S3 Buckets (Same Workflow)

```bash
# Create bucket configuration
cat > environments/dev/infrastructure/storage/my-app-bucket.yaml << 'EOF'
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: ObjectStorage
metadata:
  name: my-app-bucket
  namespace: default
spec:
  parameters:
    bucketName: portal-kombat-dev-myapp-abc123
    region: us-east-2
    environment: dev
  compositionSelector:
    matchLabels:
      bucket-type: private
  writeConnectionSecretToRef:
    name: my-app-bucket-connection
EOF

# Commit and push
git add environments/dev/infrastructure/storage/my-app-bucket.yaml
git commit -m "Add S3 bucket for my app"
git push
```

## Troubleshooting

### ArgoCD Not Syncing

```bash
# Check application status
kubectl get application dev-infrastructure -n argocd -o yaml

# Force sync if needed
kubectl patch application dev-infrastructure -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Cluster Not Being Created

```bash
# Check if XRD is available
kubectl get xrd xeksclusters.aws.plt.intelerad.io

# Check if claim exists
kubectl get ekscluster -n default

# Describe claim for events
kubectl describe ekscluster <name> -n default

# Check Crossplane logs
kubectl logs -n crossplane-system -l app=crossplane --tail=50
```

### Resources Stuck

```bash
# Check composite resource status
kubectl get xekscluster -o yaml

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-eks
```

## Adding New Infrastructure Types

To add support for new infrastructure (RDS, VPC, etc.):

1. **Add Provider** (if needed):
   - Create provider YAML in `platform/providers/`
   - Commit and push

2. **Create XRD**:
   - Define API in `platform/xrds/<category>/`
   - Commit and push

3. **Create Composition**:
   - Implement template in `platform/compositions/<category>/`
   - Commit and push

4. **Create Claims**:
   - Use new API in `environments/dev/infrastructure/<category>/`
   - Commit and push

ArgoCD handles the rest!

## Best Practices

✅ **DO**:
- Commit small, logical changes
- Use descriptive commit messages
- Test in dev before promoting to staging/prod
- Monitor ArgoCD sync status after pushing
- Use `kubectl get applications -n argocd` to see sync status

❌ **DON'T**:
- Use `kubectl apply` for infrastructure (breaks GitOps)
- Commit secrets or credentials
- Delete infrastructure files without planning
- Push directly to production without testing

## Cost Management

💰 **Remember**: Every resource you commit gets created in AWS and costs money!

- EKS cluster: ~$73/month (control plane) + EC2 costs
- S3 buckets: Storage + requests
- RDS databases: Instance costs + storage

Always delete test resources:

```bash
git rm environments/dev/infrastructure/compute/test-cluster.yaml
git commit -m "Clean up test cluster"
git push
```

## Getting Help

- Check ArgoCD UI: Get URL with `kubectl get svc -n argocd`
- View logs: `kubectl logs -n argocd <argocd-pod-name>`
- Check this repo's docs: `docs/`
- Crossplane docs: https://docs.crossplane.io/
- ArgoCD docs: https://argo-cd.readthedocs.io/
