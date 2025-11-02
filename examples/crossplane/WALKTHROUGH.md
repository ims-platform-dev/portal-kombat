# Crossplane EKS Deployment Walkthrough

This guide walks you through how Crossplane deploys an EKS cluster and what happens at each step.

## Table of Contents
1. [Understanding Crossplane Architecture](#understanding-crossplane-architecture)
2. [How Crossplane Works](#how-crossplane-works)
3. [EKS Deployment Methods](#eks-deployment-methods)
4. [Step-by-Step Deployment](#step-by-step-deployment)
5. [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

## Understanding Crossplane Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (Your EKS Cluster)                   │
│                                                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │ crossplane-system namespace                       │  │
│  │                                                    │  │
│  │  ┌──────────────┐  ┌─────────────────────────┐   │  │
│  │  │  Crossplane  │  │  AWS Provider           │   │  │
│  │  │  Controller  │  │  (provider-aws pod)     │   │  │
│  │  └──────────────┘  └─────────────────────────┘   │  │
│  │                                                    │  │
│  │  ┌──────────────────────────────────────────┐    │  │
│  │  │  ProviderConfig (AWS credentials)        │    │  │
│  │  │  Uses IAM Role: crossplane-sa-role       │    │  │
│  │  └──────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────┘  │
│                                                          │
│  ┌───────────────────────────────────────────────────┐  │
│  │ Your Resources (default namespace)                │  │
│  │                                                    │  │
│  │  - S3 Buckets                                     │  │
│  │  - VPCs                                           │  │
│  │  - EKS Clusters                                   │  │
│  │  - RDS Databases                                  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                      │
                      │ AWS API Calls
                      ▼
┌─────────────────────────────────────────────────────────┐
│ AWS Cloud                                                │
│                                                          │
│  - Creates actual infrastructure                        │
│  - VPCs, Subnets, EKS clusters, etc.                   │
└─────────────────────────────────────────────────────────┘
```

### How It Works

1. **You create a Kubernetes resource** (like an S3 bucket or EKS cluster)
2. **Crossplane controller sees it** and creates a "Managed Resource"
3. **AWS Provider pod** uses the ProviderConfig (IAM role) to call AWS APIs
4. **AWS creates the actual infrastructure**
5. **Crossplane syncs status** back to Kubernetes

## How Crossplane Works

### The Reconciliation Loop

```
┌─────────────────────────────────────────────────────────┐
│ 1. You: kubectl apply -f eks-cluster.yaml              │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Kubernetes API Server stores the resource           │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Crossplane Controller detects new resource          │
│    - Reads the spec                                     │
│    - Determines what AWS resources are needed           │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 4. AWS Provider calls AWS APIs                         │
│    - Uses IAM role credentials                          │
│    - Creates VPC, Subnets, EKS cluster, etc.           │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 5. AWS provisions the infrastructure                    │
│    - This takes time (5-15 mins for EKS)               │
└────────────────────┬────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────┐
│ 6. Crossplane polls AWS for status                     │
│    - Updates Kubernetes resource status                 │
│    - Shows "Ready: True" when complete                  │
└─────────────────────────────────────────────────────────┘
```

### Status Flow

When you create a resource, it goes through these states:

1. **Creating** - Crossplane is calling AWS APIs
2. **Available** - AWS has created the resource
3. **Ready** - Resource is fully operational and ready to use

You can watch this with:
```bash
kubectl get cluster my-eks-cluster -w
```

## EKS Deployment Methods

### Method 1: Direct AWS Resources (03-eks-cluster-simple.yaml)

**Pros:**
- Full control over every resource
- Easy to understand what's being created
- Can customize anything

**Cons:**
- Verbose (need to define VPC, subnets, security groups, IAM roles, etc.)
- More complex to maintain
- Easy to miss a required component

**When to use:**
- Learning Crossplane
- Need very specific customizations
- Building your own composition

### Method 2: Custom Composition (04-eks-cluster-custom.yaml)

**Pros:**
- Much simpler - just specify parameters
- Reusable across multiple clusters
- Standardized - same configuration every time
- Team can share compositions

**Cons:**
- Need to understand the composition first
- Less flexibility (limited to composition parameters)
- Must install composition before using

**When to use:**
- Production deployments
- Multiple similar clusters
- Team has standardized on a composition

## Step-by-Step Deployment

### Prerequisites Check

```bash
# 1. Check Crossplane is running
kubectl get pods -n crossplane-system

# Expected output:
# NAME                                    READY   STATUS    RESTARTS   AGE
# crossplane-xxxxx                        1/1     Running   0          1h
# crossplane-provider-aws-xxxxx           1/1     Running   0          30m
# crossplane-rbac-manager-xxxxx           1/1     Running   0          1h

# 2. Check AWS provider is healthy
kubectl get providers

# Expected output:
# NAME                      INSTALLED   HEALTHY   PACKAGE
# crossplane-provider-aws   True        True      xpkg.upbound.io/...

# 3. Check provider config
kubectl get providerconfig.aws.crossplane.io

# Expected output:
# NAME      AGE
# default   1h

# 4. Test provider permissions (check logs)
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws | tail -20

# Should NOT see "forbidden" or "access denied" errors
```

### Deploy a Simple S3 Bucket First

```bash
# 1. Create the bucket
kubectl apply -f examples/crossplane/01-s3-bucket.yaml

# 2. Watch the status
kubectl get bucket my-crossplane-example-bucket -w

# Initially you'll see:
# NAME                           READY   SYNCED   AGE
# my-crossplane-example-bucket   False   False    5s

# After 10-30 seconds:
# NAME                           READY   SYNCED   AGE
# my-crossplane-example-bucket   True    True     35s

# 3. Get detailed status
kubectl describe bucket my-crossplane-example-bucket

# 4. Verify in AWS (optional)
aws s3 ls | grep my-crossplane-example-bucket

# 5. Clean up
kubectl delete -f examples/crossplane/01-s3-bucket.yaml

# Crossplane will delete the bucket from AWS
```

### Deploy EKS Cluster (Method 1: Simple)

```bash
# WARNING: This creates real AWS resources and will incur costs!
# Review the file first:
cat examples/crossplane/03-eks-cluster-simple.yaml

# This file creates:
# - 1 VPC
# - 2 Public Subnets
# - 1 Internet Gateway
# - Route tables
# - 2 IAM Roles (cluster + nodes)
# - 3 IAM Policy Attachments
# - 1 Security Group
# - 1 EKS Cluster
# - 1 Node Group with 2-4 nodes

# 1. Apply the configuration
kubectl apply -f examples/crossplane/03-eks-cluster-simple.yaml

# 2. Watch the cluster creation
kubectl get cluster my-eks-cluster -w

# This will take 10-15 minutes. You'll see:
# NAME             READY   SYNCED   AGE
# my-eks-cluster   False   False    10s
# my-eks-cluster   False   True     1m
# my-eks-cluster   True    True     15m  <- Cluster is ready!

# 3. Check all managed resources
kubectl get managed

# You'll see all the AWS resources Crossplane is managing:
# - VPC
# - Subnets
# - Internet Gateway
# - Route tables
# - IAM roles
# - Security groups
# - EKS cluster
# - Node group

# 4. Get cluster details
kubectl describe cluster my-eks-cluster

# Look for:
# - Status: conditions show what's happening
# - At Provider: shows AWS resource ARNs
# - Events: shows what Crossplane is doing

# 5. Get the kubeconfig
kubectl get secret my-eks-cluster-connection -o jsonpath='{.data.kubeconfig}' | base64 -d > kubeconfig-new-cluster

# 6. Access the new cluster
export KUBECONFIG=kubeconfig-new-cluster
kubectl get nodes

# You should see 2 nodes (or however many you configured)

# 7. Switch back to management cluster
unset KUBECONFIG

# 8. Clean up (when done testing)
kubectl delete -f examples/crossplane/03-eks-cluster-simple.yaml

# Crossplane will delete everything from AWS (takes 10-15 minutes)
```

### Deploy EKS Cluster (Method 2: Custom Composition)

```bash
# 1. First, install the composition (one-time setup)
kubectl apply -f bootstrap/crossplane/crossplane-complete/templates/6-crossplane-eks-composition.yaml

# Wait for composition to be ready
kubectl get configuration

# 2. Review the custom cluster definition
cat examples/crossplane/04-eks-cluster-custom.yaml

# Notice how much simpler this is - just parameters!

# 3. Apply it
kubectl apply -f examples/crossplane/04-eks-cluster-custom.yaml

# 4. Watch the composite resource
kubectl get ekscluster my-custom-eks-cluster -w

# 5. See all the resources it creates
kubectl get managed | grep my-custom-eks-cluster

# The composition creates everything for you automatically!

# 6. Get connection details
kubectl get secret my-custom-eks-cluster-connection -o jsonpath='{.data.kubeconfig}' | base64 -d > kubeconfig-custom

# 7. Clean up
kubectl delete -f examples/crossplane/04-eks-cluster-custom.yaml
```

## Monitoring and Troubleshooting

### Check Overall Status

```bash
# All managed resources
kubectl get managed

# All crossplane resources
kubectl get crossplane

# Specific resource types
kubectl get clusters
kubectl get nodegro ups
kubectl get vpcs
kubectl get subnets
```

### Check Resource Details

```bash
# Get detailed information
kubectl describe cluster my-eks-cluster

# Look for:
# - Status.Conditions: Shows current state
# - Status.AtProvider: Shows AWS details
# - Events: Shows what happened
```

### Common Issues

#### 1. Provider shows "Not Healthy"

```bash
kubectl describe provider crossplane-provider-aws

# Check events and status
# Usually means IAM permissions are missing
```

#### 2. Resources stuck in "Creating"

```bash
# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=100

# Look for AWS API errors:
# - "Access Denied" = IAM permissions issue
# - "Quota exceeded" = AWS service limits
# - "Already exists" = Resource name collision
```

#### 3. IAM Permission Errors

The IAM role `crossplane-sa-role` needs these permissions:
- EC2: Full access for VPC, subnets, security groups
- EKS: Full access for cluster creation
- IAM: Create roles and attach policies
- CloudFormation: For some managed resources

Add the `AdministratorAccess` policy for testing, or create a custom policy with specific permissions.

#### 4. Resource Already Exists

If you see "already exists" errors:

```bash
# Option 1: Delete from AWS console first
# Option 2: Import existing resource (advanced)
# Option 3: Change the resource name
```

### Viewing Logs

```bash
# Crossplane core logs
kubectl logs -n crossplane-system -l app=crossplane

# AWS provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws

# Follow logs in real-time
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws -f
```

### Debugging Commands

```bash
# Get all events in crossplane-system
kubectl get events -n crossplane-system --sort-by='.lastTimestamp'

# Check if resources are being synced
kubectl get managed -o wide

# See raw resource YAML
kubectl get cluster my-eks-cluster -o yaml

# Check AWS provider configuration
kubectl get providerconfig default -o yaml
```

## What Happens During EKS Creation

### Timeline (Approximate)

| Time | What's Happening | Status |
|------|-----------------|---------|
| 0s | You apply the YAML | - |
| 1-5s | Crossplane validates and creates Managed Resources | SYNCED=False |
| 5-30s | AWS Provider calls AWS APIs | SYNCED=True, READY=False |
| 30s-2m | VPC, Subnets, IGW created | Some resources READY=True |
| 2m-5m | IAM roles created and policies attached | - |
| 5m-12m | EKS control plane provisioning | READY=False |
| 12m-15m | Node group created, nodes joining | READY=False |
| 15m+ | Everything ready! | READY=True |

### Behind the Scenes

```
You: kubectl apply -f eks-cluster.yaml
│
├─> Crossplane: Creates Cluster object in Kubernetes
│   └─> AWS Provider sees new Cluster
│       ├─> Calls eks.CreateCluster API
│       ├─> AWS: Provisions control plane (5-10 mins)
│       └─> Polls eks.DescribeCluster until ready
│
├─> Crossplane: Creates NodeGroup object
│   └─> AWS Provider sees new NodeGroup
│       ├─> Calls eks.CreateNodegroup API
│       ├─> AWS: Launches EC2 instances (3-5 mins)
│       └─> Polls eks.DescribeNodegroup until ready
│
└─> Crossplane: Updates Cluster status to READY=True
    └─> You: kubectl get cluster shows Ready!
```

## Cost Considerations

Creating an EKS cluster incurs AWS charges:

- **EKS Control Plane**: ~$73/month ($0.10/hour)
- **Worker Nodes (t3.medium x2)**: ~$60/month
- **Data Transfer**: Variable
- **EBS Volumes**: ~$2/month

**Total**: ~$135/month minimum

Always delete test clusters when done:
```bash
kubectl delete -f examples/crossplane/03-eks-cluster-simple.yaml
```

## Next Steps

1. **Start small**: Deploy the S3 bucket first
2. **Understand compositions**: Read about how they work
3. **Create custom compositions**: For your specific needs
4. **Integrate with ArgoCD**: Let ArgoCD manage crossplane resources
5. **Build a platform**: Create self-service infrastructure for your team

## Additional Resources

- [Crossplane Docs](https://docs.crossplane.io/)
- [AWS Provider Docs](https://marketplace.upbound.io/providers/crossplane-contrib/provider-aws/)
- [Composition Guide](https://docs.crossplane.io/latest/concepts/compositions/)
- [Best Practices](https://docs.crossplane.io/knowledge-base/guides/best-practices/)
