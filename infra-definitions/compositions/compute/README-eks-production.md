# EKS Production Composition - Architecture Documentation

This document provides comprehensive architecture documentation for the **EKS Production Composition** (`ekscluster-production`), which implements the `XEKSCluster` XRD to create fully-featured, production-ready Amazon EKS clusters.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Key Patterns](#key-patterns)
- [Supported Features](#supported-features)
- [Usage Examples](#usage-examples)
- [Customization Guide](#customization-guide)
- [Limitations](#limitations)
- [Future Enhancements](#future-enhancements)

---

## Overview

The EKS Production Composition is a Crossplane composition that declaratively creates and manages complete Amazon EKS clusters through a simple Kubernetes API. It abstracts the complexity of EKS cluster provisioning, including control plane setup, node groups, add-ons, IAM configuration, and Pod Identity management.

### Purpose

- **Simplify EKS provisioning**: Reduce multi-step AWS console workflows to a single Kubernetes resource
- **Enforce best practices**: Embed production-ready defaults for security, high availability, and observability
- **Enable GitOps workflows**: Manage infrastructure as code through declarative Kubernetes manifests
- **Provide self-service capabilities**: Allow teams to create clusters without deep AWS expertise

### Design Philosophy

1. **Sensible defaults**: Minimal configuration required, with production-ready defaults
2. **Progressive disclosure**: Simple for basic use cases, powerful for advanced scenarios
3. **Cloud-agnostic API**: Abstract AWS-specific details behind a consistent interface
4. **Composable**: Integrate with other Portal Kombat compositions (VPC, networking, storage)

### When to Use This Composition

**Use the EKS Production Composition when:**
- Creating new EKS clusters in a GitOps-managed environment
- Standardizing EKS cluster configuration across teams
- Need integrated Pod Identity (IRSA) and cluster add-ons
- Want automated lifecycle management (upgrades, scaling, add-ons)

**Do NOT use this composition when:**
- Requiring highly customized cluster configurations not supported by the API
- Need more than one managed node group (current limitation - see [Limitations](#limitations))
- Operating outside a Crossplane-managed Kubernetes environment

---

## Architecture

### Component Breakdown

The composition creates 30-35 managed AWS resources per cluster, organized into the following components:

#### 1. Control Plane (EKS Cluster)

**Resources Created:**
- **EKS Cluster** (`eks.aws.upbound.io/v1beta2/Cluster`): The Kubernetes control plane
- **Cluster IAM Role** (`iam.aws.upbound.io/v1beta1/Role`): IAM role for EKS service
- **2x IAM Policy Attachments** (`iam.aws.upbound.io/v1beta1/RolePolicyAttachment`):
  - `AmazonEKSClusterPolicy`: Core EKS permissions
  - `AmazonEKSVPCResourceController`: ENI management for pods

**Key Features:**
- Kubernetes version selection (1.30, 1.31, 1.32)
- VPC integration with existing VPCs and subnets
- Private or public API endpoint access
- IRSA (IAM Roles for Service Accounts) via OIDC provider
- Access entry API for modern IAM-based authentication
- Cluster upgrade policy (STANDARD or EXTENDED support)

**Status Propagation:**
- `status.clusterRoleArn`: IAM role ARN for the cluster
- `status.endpoint`: Kubernetes API server endpoint
- `status.oidcIssuerUrl`: OIDC provider URL for IRSA

---

#### 2. Node Groups (Managed Worker Nodes)

**Resources Created (per node group):**
- **Node Group** (`eks.aws.upbound.io/v1beta2/NodeGroup`): Managed node group
- **Launch Template** (`ec2.aws.upbound.io/v1beta2/LaunchTemplate`): Custom EC2 configuration
- **Node IAM Role** (`iam.aws.upbound.io/v1beta1/Role`): IAM role for worker nodes
- **3x IAM Policy Attachments** (`iam.aws.upbound.io/v1beta1/RolePolicyAttachment`):
  - `AmazonEKSWorkerNodePolicy`: Core node permissions
  - `AmazonEKS_CNI_Policy`: VPC-CNI networking
  - `AmazonEC2ContainerRegistryReadOnly`: ECR image pull

**Key Features:**
- Instance type selection (single or multiple types for flexibility)
- Auto Scaling configuration (min/max/desired capacity)
- Custom AMI support (AL2, AL2023, ARM64, GPU)
- SSH key pair for node access
- Custom user data (cloud-init) for node initialization
- Block device mapping for custom root volume size/type
- Node labels and taints for workload scheduling

**Node Group Defaults:**
- AMI: `AL2023_x86_64_STANDARD` (latest EKS-optimized Amazon Linux)
- Root volume: 20 GB, gp3, encrypted
- Cloud-init: RAID0 ephemeral storage, optimized kubelet settings

**Status Propagation:**
- `status.nodeRoleArn`: IAM role ARN for nodes

**Current Limitation:** Only ONE node group supported per cluster (see [Limitations](#limitations))

---

#### 3. Cluster Add-ons (System Components)

**Resources Created (per add-on):**
- **Addon** (`eks.aws.upbound.io/v1beta2/Addon`): EKS-managed add-on

**Default Add-ons (automatically enabled):**

1. **CoreDNS** (`coredns`)
   - Cluster DNS service for service discovery
   - Version: Latest compatible with Kubernetes version

2. **VPC-CNI** (`vpc-cni`)
   - AWS VPC networking plugin for pod IP assignment
   - Supports custom networking and prefix delegation
   - Version: Latest compatible with Kubernetes version

3. **kube-proxy** (`kube-proxy`)
   - Kubernetes network proxy for service load balancing
   - Version: Latest compatible with Kubernetes version

4. **Pod Identity Agent** (`eks-pod-identity-agent`)
   - Enables EKS Pod Identity for IRSA v2
   - Required for Pod Identity associations
   - Version: Latest compatible with Kubernetes version

**Optional Add-ons:**

5. **EFS CSI Driver** (`aws-efs-csi-driver`)
   - Enables EFS persistent storage for pods
   - Disabled by default (enable via `clusterAddons.awsEfsCsiDriver.enabled: true`)
   - Requires Pod Identity role with `AmazonEFSCSIDriverPolicy`

**Add-on Configuration:**
- Version pinning: Specify exact add-on version or use latest
- Conflict resolution: `OVERWRITE`, `NONE`, or `PRESERVE`
- Service account role ARN: Automatically linked to Pod Identity roles

**See:** [AWS EKS Add-ons Documentation](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html)

---

#### 4. IAM (Pod Identity Roles)

**Resources Created (per Pod Identity role):**
- **Pod Identity IAM Role** (`iam.aws.upbound.io/v1beta1/Role`): IAM role for service account
- **IAM Policy Attachment** (`iam.aws.upbound.io/v1beta1/RolePolicyAttachment`): Attach managed/custom policies
- **Pod Identity Association** (`eks.aws.upbound.io/v1beta1/PodIdentityAssociation`): Link role to Kubernetes SA

**Supported Pod Identity Roles:**

1. **Cluster Autoscaler** (optional)
   - Kubernetes service account: `cluster-autoscaler` (namespace: `kube-system`)
   - Enables auto-scaling of node groups based on pod demand
   - Policy: `AWSClusterAutoscalerPolicy` (custom, created separately)
   - Enable via: `podIdentityRoles[key=cluster-autoscaler].attachClusterAutoscalerPolicy: true`

2. **EFS CSI Driver** (optional, auto-enabled if EFS add-on enabled)
   - Kubernetes service account: `efs-csi-controller-sa` (namespace: `kube-system`)
   - Allows EFS CSI driver to create/manage EFS access points
   - Policy: `AmazonEFSCSIDriverPolicy` (AWS managed)

3. **AWS Load Balancer Controller** (optional)
   - Kubernetes service account: `aws-load-balancer-controller` (namespace: `kube-system`)
   - Enables ALB/NLB creation from Kubernetes Ingress/Service resources
   - Policy: `AWSLoadBalancerControllerPolicy` (custom, created separately)
   - Enable via: `podIdentityRoles[key=lb-controller].attachLoadBalancerControllerPolicy: true`

4. **VPC-CNI** (optional)
   - Kubernetes service account: `aws-node` (namespace: `kube-system`)
   - Advanced VPC-CNI features (custom networking, prefix delegation)
   - Policy: `AmazonEKS_CNI_Policy` (AWS managed)
   - Enable via: `podIdentityRoles[key=vpc-cni].enabled: true`

**Pod Identity vs IRSA:**
- Pod Identity is the modern approach (EKS Pod Identity, IRSA v2)
- Automatically configured when `enableIrsa: true` (default)
- No manual OIDC provider or IAM trust policy configuration needed

**See:** [AWS EKS Pod Identity Documentation](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)

---

#### 5. Networking (VPC Integration)

The composition integrates with existing VPC infrastructure. It does NOT create VPCs, subnets, or route tables.

**Required Network Resources (pre-existing):**
- VPC with sufficient IP space
- Minimum 2 subnets (recommended: 3+ across multiple AZs)
- Private subnets recommended for production workloads
- Internet access for nodes (NAT Gateway or VPC endpoints)

**VPC Configuration Options:**
- **Cluster Endpoint Access**: Public (development), Private (production), or both
- **Subnet Selection**: Control plane and node placement
- **Security Groups**: Auto-created by EKS or manually specified

**Network Features:**
- **VPC-CNI Custom Networking**: Separate CIDR for pods (via `vpcCniConfig`)
- **ENI Configuration**: Subnet mapping for pod ENIs
- **Cluster Security Group**: Automatically managed by EKS

**Example VPC Configuration:**

```yaml
vpcConfig:
  vpcId: vpc-0123456789abcdef0
  subnetIds:
    - subnet-0aaaaaaaaaaaaaaaa  # Private subnet in us-east-2a
    - subnet-0bbbbbbbbbbbbbbb   # Private subnet in us-east-2b
    - subnet-0ccccccccccccccc   # Private subnet in us-east-2c
  clusterEndpointPublicAccess: false  # Private API only
```

**See:** [EKS VPC Considerations](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)

---

#### 6. Storage (EFS Integration - Optional)

When EFS CSI driver is enabled, the composition automatically configures:

**Resources Created:**
- **EFS CSI Driver Add-on**: Installed as cluster add-on
- **Pod Identity Role**: IAM role for EFS CSI driver service account
- **Policy Attachment**: `AmazonEFSCSIDriverPolicy`

**Usage (requires separate EFS file system):**

1. Create EFS file system (outside composition or via separate EFS composition)
2. Create StorageClass for dynamic provisioning:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-12345678
  directoryPerms: "700"
```

3. Use in PersistentVolumeClaim:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-efs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
```

**See:** [AWS EFS CSI Driver Documentation](https://github.com/kubernetes-sigs/aws-efs-csi-driver)

---

### Resource Count Estimate

**Minimal Configuration** (single node group, no optional features):
- 2 IAM Roles
- 5 RolePolicyAttachments
- 1 EKS Cluster
- 1 LaunchTemplate
- 1 NodeGroup
- 4 Addons (coredns, vpc-cni, kube-proxy, pod-identity-agent)
- **Total: ~14 resources**

**Full-Featured Configuration** (all optional features enabled):
- 6 IAM Roles (cluster, node, 4x pod identity)
- 10 RolePolicyAttachments
- 1 EKS Cluster
- 1 LaunchTemplate
- 1 NodeGroup
- 5 Addons (+ efs-csi)
- 4 PodIdentityAssociations
- **Total: ~28 resources**

**Additional resources scale with:**
- Number of access entries (additional IAM principals)
- Custom security groups
- Additional tags

---

### Dependency Relationships

The composition manages resource creation order automatically through Crossplane's dependency resolution:

```
1. IAM Roles (cluster-role, node-role)
   ↓
2. IAM Policy Attachments (depends on roles)
   ↓
3. EKS Cluster (depends on cluster-role)
   ↓
4. LaunchTemplate (independent, but logically after cluster)
   ↓
5. NodeGroup (depends on cluster, node-role, launch-template)
   ↓
6. Addons (depends on cluster)
   ↓
7. Pod Identity Roles (depends on cluster for OIDC provider)
   ↓
8. Pod Identity Associations (depends on cluster, pod-identity-roles)
```

**Typical Creation Timeline:**
- IAM resources: ~30 seconds
- EKS cluster: ~10-12 minutes
- Node groups: ~3-5 minutes (after cluster ready)
- Addons: ~2-3 minutes (after cluster ready)
- **Total: ~15-20 minutes**

---

## Key Patterns

### 1. PatchSets for Reusable Configuration

**Problem:** Repetitive patches across many resources (e.g., region, tags, provider config)

**Solution:** PatchSets define reusable patch configurations applied to multiple resources.

**Example:**

```yaml
patchSets:
  - name: region
    patches:
      - type: FromCompositeFieldPath
        fromFieldPath: spec.parameters.region
        toFieldPath: spec.forProvider.region
        policy:
          fromFieldPath: Optional

  - name: standard-tags
    patches:
      - type: FromCompositeFieldPath
        fromFieldPath: spec.parameters.tags
        toFieldPath: spec.forProvider.tags
        policy:
          toFieldPath: MergeObjects
```

**Usage in Resources:**

```yaml
resources:
  - name: eks-cluster
    patches:
      - type: PatchSet
        patchSetName: region
      - type: PatchSet
        patchSetName: standard-tags
```

**Benefits:**
- DRY principle: Define once, use everywhere
- Consistency: All resources get same configuration
- Maintainability: Update in one place

---

### 2. Label Selectors for Resource Relationships

**Problem:** Dynamic resource references (e.g., node group needs to reference IAM role)

**Solution:** Use label selectors to create loose coupling between resources.

**Example:**

```yaml
# IAM Role definition
- name: node-role
  base:
    metadata:
      labels:
        portal-kombat.io/eks-component: node-role

# NodeGroup referencing role via selector
- name: node-group-0
  base:
    spec:
      forProvider:
        nodeRoleArnSelector:
          matchControllerRef: true
          matchLabels:
            portal-kombat.io/eks-component: node-role
```

**Benefits:**
- Decoupling: No hardcoded ARNs or names
- Dynamic resolution: Crossplane resolves references at runtime
- Flexibility: Easy to change references without updating ARNs

---

### 3. Status Field Propagation

**Problem:** Need to expose AWS resource attributes to users (e.g., cluster endpoint, OIDC issuer URL)

**Solution:** Use `ToCompositeFieldPath` patches to propagate status fields from managed resources to the composite.

**Example:**

```yaml
- name: eks-cluster
  patches:
    # Propagate cluster endpoint to status
    - type: ToCompositeFieldPath
      fromFieldPath: status.atProvider.endpoint
      toFieldPath: status.endpoint

    # Propagate OIDC issuer URL
    - type: ToCompositeFieldPath
      fromFieldPath: status.atProvider.identity[0].oidc[0].issuer
      toFieldPath: status.oidcIssuerUrl
```

**Usage by Users:**

```bash
kubectl get ekscluster my-cluster -o jsonpath='{.status.endpoint}'
# Output: https://ABC123.gr7.us-east-2.eks.amazonaws.com
```

**Benefits:**
- Visibility: Users can access important resource attributes
- Integration: Other tools can read status fields for automation
- Debugging: Status fields help troubleshoot issues

---

### 4. Connection Secret Generation

**Problem:** Users need credentials to access created cluster (kubeconfig, endpoint, CA cert)

**Solution:** Use `connectionDetails` to publish sensitive data to a Kubernetes Secret.

**XRD Definition:**

```yaml
connectionSecretKeys:
  - kubeconfig
  - endpoint
  - ca-certificate-authority-data
  - oidc-issuer-url
  - cluster-name
  - region
```

**Composition Patches:**

```yaml
- name: eks-cluster
  connectionDetails:
    - name: kubeconfig
      fromConnectionSecretKey: kubeconfig
    - name: endpoint
      fromFieldPath: status.atProvider.endpoint
    - name: ca-certificate-authority-data
      fromFieldPath: status.atProvider.certificateAuthority[0].data
```

**User Claim:**

```yaml
spec:
  writeConnectionSecretToRef:
    name: my-cluster-connection
    namespace: default
```

**Accessing Connection Secret:**

```bash
kubectl get secret my-cluster-connection -n default \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > kubeconfig

export KUBECONFIG=./kubeconfig
kubectl get nodes
```

**Benefits:**
- Security: Sensitive data stored in Kubernetes Secrets
- Automation: Easy integration with GitOps tools
- Standardization: Consistent secret format across compositions

---

### 5. Conditional Resource Creation

**Problem:** Some resources should only be created when specific features are enabled (e.g., EFS CSI driver)

**Solution:** Use `readinessChecks` and conditional patches to enable/disable resources.

**Example:**

```yaml
- name: addon-efs-csi-driver
  patches:
    # Only create if awsEfsCsiDriver.enabled = true
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.clusterAddons.awsEfsCsiDriver.enabled
      toFieldPath: spec.forProvider.addonName
      transforms:
        - type: string
          string:
            type: Format
            fmt: "%s"
            convert: ToLower
      policy:
        fromFieldPath: Required  # Skip resource if field missing
```

**Alternative Pattern (using readinessChecks):**

```yaml
readinessChecks:
  - type: None  # Skip readiness check if resource not created
```

**Benefits:**
- Flexibility: Users opt-in to expensive or complex features
- Resource efficiency: Don't create unnecessary resources
- Progressive disclosure: Simple defaults, advanced options available

---

## Supported Features

### Core Features (Enabled by Default)

- **Kubernetes Version Selection**: 1.30, 1.31, 1.32 (default: 1.32)
- **VPC Integration**: Use existing VPCs and subnets
- **Private API Endpoint**: Cluster API private by default
- **IRSA (IAM Roles for Service Accounts)**: Automatic OIDC provider setup
- **Access Entry Authentication**: Modern IAM-based cluster access (API mode)
- **Managed Node Groups**: Auto Scaling Groups with EKS lifecycle management
- **Custom Launch Templates**: User data, block devices, SSH keys
- **Cluster Add-ons**: coredns, vpc-cni, kube-proxy, pod-identity-agent
- **Connection Secrets**: Automatic kubeconfig generation
- **Resource Tagging**: Standard tags + custom tags

### Optional Features (Opt-In)

- **EFS CSI Driver**: Enable persistent ReadWriteMany storage
- **Pod Identity Roles**: Cluster Autoscaler, EFS CSI, LB Controller, VPC-CNI
- **VPC-CNI Custom Networking**: Separate CIDR for pods
- **Public API Endpoint**: Allow public access to Kubernetes API
- **Extended Support**: 18-month Kubernetes version support (vs 14-month standard)
- **SSH Access to Nodes**: Specify EC2 key pair
- **Custom Node Labels**: Workload scheduling metadata
- **Custom Node Taints**: Node affinity/anti-affinity
- **Multiple Instance Types**: Mixed instance types in node group
- **Custom Root Volume**: Size, type, encryption
- **Access Entries**: Grant additional IAM principals cluster access

### Advanced Features (Requires Customization)

- **Custom AMI**: Specify custom EKS-optimized AMI IDs
- **User Data (cloud-init)**: Custom node initialization scripts
- **Security Groups**: Attach additional security groups to nodes
- **CloudWatch Logging**: Enable control plane logs (audit, authenticator, API server)
- **Encryption**: KMS key for secrets encryption at rest

### Not Supported (Limitations)

- **Multiple Node Groups**: Only ONE node group per cluster (see [Limitations](#limitations))
- **Fargate Profiles**: Use separate Fargate composition (future)
- **Spot Instances**: Requires custom launch template configuration
- **Windows Nodes**: Not supported in current composition
- **Self-Managed Node Groups**: Use EKS managed node groups only

---

## Usage Examples

### Example 1: Minimal Development Cluster

**File:** `/examples/compute/eks-cluster-minimal.yaml`

```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EKSCluster
metadata:
  name: dev-cluster
  namespace: default
spec:
  writeConnectionSecretToRef:
    name: dev-cluster-connection
    namespace: default
  parameters:
    clusterName: dev-cluster
    vpcConfig:
      vpcId: vpc-0123456789abcdef0
      subnetIds:
        - subnet-0aaaaaaaaaaaaaaaa
        - subnet-0bbbbbbbbbbbbbbb
        - subnet-0ccccccccccccccc
    nodeGroups:
      - name: default-nodes
        instanceTypes: [t3.medium]
        minSize: 1
        maxSize: 5
        desiredSize: 2
```

**Features:**
- Latest Kubernetes version (1.32)
- Private API endpoint
- 2 nodes (t3.medium)
- All default add-ons enabled
- No optional features

**Use Cases:** Local development, testing, proof-of-concept

---

### Example 2: Production Cluster with Autoscaling

**File:** `/examples/compute/eks-cluster-comprehensive.yaml` (excerpt)

```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EKSCluster
metadata:
  name: prod-cluster
  namespace: default
spec:
  writeConnectionSecretToRef:
    name: prod-cluster-connection
    namespace: default
  parameters:
    clusterName: prod-cluster
    clusterVersion: "1.32"
    region: us-east-2

    vpcConfig:
      vpcId: vpc-0123456789abcdef0
      subnetIds:
        - subnet-0aaaaaaaaaaaaaaaa
        - subnet-0bbbbbbbbbbbbbbb
        - subnet-0ccccccccccccccc
      clusterEndpointPublicAccess: false

    enableIrsa: true
    authenticationMode: API
    enableClusterCreatorAdminPermissions: true

    clusterUpgradePolicy:
      supportType: EXTENDED  # 18-month support

    nodeGroups:
      - name: kube-nodes
        instanceTypes: [m5.large, m5.xlarge]
        minSize: 3
        maxSize: 20
        desiredSize: 6
        labels:
          environment: production
          workload-type: general
        blockDeviceMappings:
          - deviceName: /dev/xvda
            volumeSize: 100
            volumeType: gp3
            encrypted: true

    clusterAddons:
      awsEfsCsiDriver:
        enabled: true

    podIdentityRoles:
      - key: cluster-autoscaler
        attachClusterAutoscalerPolicy: true
      - key: lb-controller
        attachLoadBalancerControllerPolicy: true

    tags:
      Environment: production
      ManagedBy: Crossplane
      Project: portal-kombat
```

**Features:**
- Extended support (18 months)
- Private API only
- Multiple instance types (cost optimization)
- Large node group (3-20 nodes)
- EFS CSI driver enabled
- Cluster Autoscaler + Load Balancer Controller
- Custom node labels for scheduling
- 100 GB root volumes

**Use Cases:** Production workloads, multi-tenant clusters, enterprise deployments

---

### Example 3: Cluster with VPC-CNI Custom Networking

**File:** Custom example (not in repository)

```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: EKSCluster
metadata:
  name: custom-networking-cluster
spec:
  writeConnectionSecretToRef:
    name: custom-networking-cluster-connection
    namespace: default
  parameters:
    clusterName: custom-networking-cluster

    vpcConfig:
      vpcId: vpc-0123456789abcdef0
      subnetIds:
        - subnet-0aaaaaaaaaaaaaaaa  # Node subnets
        - subnet-0bbbbbbbbbbbbbbb

    nodeGroups:
      - name: nodes
        instanceTypes: [m5.large]
        minSize: 3
        maxSize: 10
        desiredSize: 5

    # VPC-CNI custom networking configuration
    vpcCniConfig:
      enableCustomNetworking: true
      eniConfigSubnets:
        us-east-2a: subnet-0ddddddddddddddd  # Pod subnets (separate CIDR)
        us-east-2b: subnet-0eeeeeeeeeeeeeee
        us-east-2c: subnet-0fffffffffffffffffff

    # Enable VPC-CNI Pod Identity role
    podIdentityRoles:
      - key: vpc-cni
        enabled: true
```

**Features:**
- Separate CIDR for pods (avoids IP exhaustion)
- ENIConfig per availability zone
- VPC-CNI with Pod Identity

**Use Cases:** Large clusters (>1000 pods), IP address conservation, multi-tenant networks

---

### Example 4: Accessing Created Cluster

After creating a cluster, extract the connection secret:

```bash
# Extract kubeconfig
kubectl get secret my-cluster-connection -n default \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/my-cluster-kubeconfig

# Set KUBECONFIG environment variable
export KUBECONFIG=/tmp/my-cluster-kubeconfig

# Verify access
kubectl get nodes

# Expected output:
# NAME                                       STATUS   ROLES    AGE   VERSION
# ip-10-0-1-123.us-east-2.compute.internal   Ready    <none>   5m    v1.32.0-eks-...
# ip-10-0-2-234.us-east-2.compute.internal   Ready    <none>   5m    v1.32.0-eks-...

# Check cluster info
kubectl cluster-info

# Deploy test workload
kubectl run nginx --image=nginx --restart=Never
kubectl get pods
```

---

## Customization Guide

### Adding a New Node Group Type

**Current Limitation:** The composition supports only ONE node group. To add multiple node groups, you must either:

1. **Manually create additional node groups** outside Crossplane:

```bash
aws eks create-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name gpu-nodes \
  --subnets subnet-xxx subnet-yyy \
  --node-role arn:aws:iam::123456789012:role/my-cluster-node-role \
  --instance-types p3.2xlarge \
  --scaling-config minSize=0,maxSize=10,desiredSize=2
```

2. **Wait for array expansion support** (see [Future Enhancements](#future-enhancements))

---

### Adding a New Cluster Add-on

To add support for a new EKS add-on:

1. **Update XRD** to include add-on configuration:

```yaml
# File: infra-definitions/xrds/compute/xrd-eks-cluster.yaml
clusterAddons:
  properties:
    myNewAddon:
      type: object
      properties:
        enabled:
          type: boolean
          default: false
        version:
          type: string
```

2. **Add add-on resource to composition**:

```yaml
# File: infra-definitions/compositions/compute/eks-production.yaml
- name: addon-my-new-addon
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.clusterName
      toFieldPath: spec.forProvider.clusterNameSelector.matchLabels[portal-kombat.io/eks-component]
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.clusterAddons.myNewAddon.enabled
      toFieldPath: metadata.annotations[crossplane.io/enabled]
  base:
    apiVersion: eks.aws.upbound.io/v1beta2
    kind: Addon
    spec:
      forProvider:
        addonName: my-new-addon
        clusterNameSelector:
          matchControllerRef: true
          matchLabels:
            portal-kombat.io/eks-component: cluster
```

3. **Test with example claim**:

```yaml
clusterAddons:
  myNewAddon:
    enabled: true
    version: "v1.0.0"
```

---

### Adding a New Pod Identity Role

To add a new Pod Identity role (e.g., for AWS Secrets Manager):

1. **Update XRD** to include role configuration:

```yaml
# File: infra-definitions/xrds/compute/xrd-eks-cluster.yaml
podIdentityRoles:
  items:
    properties:
      attachSecretsManagerPolicy:
        type: boolean
        description: Attach AmazonSSMReadOnlyAccess policy for Secrets Manager
```

2. **Add IAM role to composition**:

```yaml
- name: pod-identity-role-secrets-manager
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.clusterName
      toFieldPath: spec.forProvider.name
      transforms:
        - type: string
          string:
            fmt: "%s-secrets-manager-role"
  base:
    apiVersion: iam.aws.upbound.io/v1beta1
    kind: Role
    spec:
      forProvider:
        assumeRolePolicy: |
          {
            "Version": "2012-10-17",
            "Statement": [{
              "Effect": "Allow",
              "Principal": {"Service": "pods.eks.amazonaws.com"},
              "Action": ["sts:AssumeRole", "sts:TagSession"]
            }]
          }
```

3. **Add policy attachment**:

```yaml
- name: pod-identity-policy-secrets-manager
  base:
    apiVersion: iam.aws.upbound.io/v1beta1
    kind: RolePolicyAttachment
    spec:
      forProvider:
        policyArn: arn:aws:iam::aws:policy/SecretsManagerReadWrite
        roleSelector:
          matchLabels:
            portal-kombat.io/eks-component: pod-identity-secrets-manager
```

4. **Add Pod Identity association**:

```yaml
- name: pod-identity-assoc-secrets-manager
  base:
    apiVersion: eks.aws.upbound.io/v1beta1
    kind: PodIdentityAssociation
    spec:
      forProvider:
        namespace: default
        serviceAccount: secrets-manager-sa
        clusterNameSelector:
          matchLabels:
            portal-kombat.io/eks-component: cluster
        roleArnSelector:
          matchLabels:
            portal-kombat.io/eks-component: pod-identity-secrets-manager
```

---

### Extending Cloud-Init User Data

To customize node initialization (e.g., install monitoring agents):

1. **Update XRD** to include user data field:

```yaml
nodeGroups:
  items:
    properties:
      additionalUserData:
        type: string
        description: Additional cloud-init user data (appended to default)
```

2. **Modify launch template patch** to include custom user data:

```yaml
- name: node-launch-template-0
  patches:
    - type: FromCompositeFieldPath
      fromFieldPath: spec.parameters.nodeGroups[0].additionalUserData
      toFieldPath: spec.forProvider.userData
      transforms:
        - type: string
          string:
            type: Format
            fmt: |
              #!/bin/bash
              # Default user data
              /etc/eks/bootstrap.sh my-cluster
              # Custom user data
              %s
```

3. **Use in claim**:

```yaml
nodeGroups:
  - name: nodes
    additionalUserData: |
      yum install -y amazon-cloudwatch-agent
      systemctl start amazon-cloudwatch-agent
```

---

## Limitations

### 1. Single Node Group Only

**Problem:** The composition supports only ONE managed node group per cluster.

**Root Cause:** Crossplane `function-patch-and-transform` does not support native array iteration. The composition uses hardcoded index `[0]` for node group array access.

**Current Code:**

```yaml
- type: FromCompositeFieldPath
  fromFieldPath: spec.parameters.nodeGroups[0].instanceTypes  # Hardcoded [0]
  toFieldPath: spec.forProvider.instanceTypes
```

**Workarounds:**

1. **Use multiple instance types in single node group** for workload diversity:

```yaml
nodeGroups:
  - name: mixed-nodes
    instanceTypes: [m5.large, m5.xlarge, m5.2xlarge]
```

2. **Manually create additional node groups** via AWS CLI/Console (not GitOps-managed)

3. **Create multiple EKSCluster resources** (not recommended - operationally complex)

**Planned Fix:** Migrate to `function-go-templating` which supports native Go template loops (see [Future Enhancements](#future-enhancements))

---

### 2. Add-on Version Management

**Problem:** Add-on versions are not automatically updated when new versions are released.

**Impact:** May use outdated add-on versions unless explicitly specified.

**Workaround:** Regularly update composition defaults or specify versions in claims:

```yaml
clusterAddons:
  coredns:
    version: "v1.11.1-eksbuild.9"  # Explicit version
```

**See:** Check latest versions via AWS CLI:

```bash
aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.32
```

---

### 3. No Fargate Profile Support

**Problem:** Composition does not support AWS Fargate profiles for serverless pod execution.

**Workaround:** Create Fargate profiles manually or use a separate composition (future).

**See:** [AWS EKS Fargate Documentation](https://docs.aws.amazon.com/eks/latest/userguide/fargate.html)

---

### 4. Limited Access Entry Support

**Problem:** Access entries are defined in XRD but not fully implemented in composition.

**Workaround:** Use `kubectl` to manually grant cluster access:

```bash
aws eks create-access-entry \
  --cluster-name my-cluster \
  --principal-arn arn:aws:iam::123456789012:role/MyRole \
  --kubernetes-groups system:masters
```

---

### 5. CloudWatch Logging Not Enabled by Default

**Problem:** Control plane logs (API server, audit, authenticator) are disabled by default.

**Impact:** Limited visibility into cluster control plane operations.

**Workaround:** Enable via AWS Console or CLI after cluster creation:

```bash
aws eks update-cluster-config \
  --name my-cluster \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator"],"enabled":true}]}'
```

**Future Enhancement:** Add `clusterLogging` field to XRD and composition.

---

## Future Enhancements

### 1. Array Expansion with Go Templating (High Priority)

**Goal:** Support multiple node groups using `function-go-templating`.

**Current Issue:** `function-patch-and-transform` cannot iterate over arrays.

**Proposed Solution:**

```yaml
# Future composition with Go templating
spec:
  mode: Pipeline
  pipeline:
    - step: render-node-groups
      functionRef:
        name: function-go-templating
      input:
        apiVersion: gotemplating.fn.crossplane.io/v1beta1
        kind: GoTemplate
        source: Inline
        inline:
          template: |
            {{ range $i, $ng := .observed.composite.resource.spec.parameters.nodeGroups }}
            ---
            apiVersion: eks.aws.upbound.io/v1beta2
            kind: NodeGroup
            metadata:
              name: {{ $.observed.composite.resource.metadata.name }}-{{ $ng.name }}-{{ $i }}
            spec:
              forProvider:
                clusterName: {{ $.observed.composite.resource.spec.parameters.clusterName }}
                nodeGroupName: {{ $.observed.composite.resource.spec.parameters.clusterName }}-{{ $ng.name }}-{{ $i }}
                instanceTypes: {{ toJson $ng.instanceTypes }}
                scalingConfig:
                  - minSize: {{ $ng.minSize }}
                    maxSize: {{ $ng.maxSize }}
                    desiredSize: {{ $ng.desiredSize }}
            {{ end }}
```

**Benefits:**
- Support unlimited node groups
- Cleaner, more maintainable code
- Unlock other array-based features (access entries, security groups)

**References:**
- [function-go-templating GitHub](https://github.com/crossplane-contrib/function-go-templating)
- [Crossplane Functions Documentation](https://docs.crossplane.io/latest/concepts/composition-functions/)

---

### 2. Fargate Profile Support

**Goal:** Add support for serverless pod execution via AWS Fargate.

**Proposed XRD Field:**

```yaml
fargateProfiles:
  type: array
  items:
    type: object
    properties:
      name:
        type: string
      namespaceSelectors:
        type: array
        items:
          type: object
          properties:
            namespace:
              type: string
            labels:
              type: object
```

---

### 3. Spot Instance Support

**Goal:** Enable EC2 Spot instances for cost optimization.

**Proposed XRD Field:**

```yaml
nodeGroups:
  items:
    properties:
      capacityType:
        type: string
        enum: [ON_DEMAND, SPOT]
        default: ON_DEMAND
```

---

### 4. Cluster Autoscaler Automatic Installation

**Goal:** Automatically install Cluster Autoscaler via Helm chart when Pod Identity role is enabled.

**Proposed Implementation:**
- Add `function-helm` to composition pipeline
- Install `cluster-autoscaler` Helm chart conditionally

---

### 5. Integrated VPC Creation

**Goal:** Optionally create VPC, subnets, and route tables as part of cluster composition.

**Proposed Pattern:** Use composition references to link VPC composition with EKS composition.

---

### 6. GitOps Integration (ArgoCD/Flux)

**Goal:** Automatically deploy ArgoCD or Flux to created clusters.

**Proposed Implementation:**
- Add `gitOpsOperator` field to XRD
- Use `function-helm` to install operator after cluster ready

---

### 7. Observability Stack (Prometheus/Grafana)

**Goal:** Optionally deploy monitoring stack to clusters.

**Proposed Implementation:**
- Add `observability` field to XRD
- Use Helm charts to install kube-prometheus-stack

---

## Testing

To test the composition before deploying:

```bash
# Run composition test script
./scripts/test-eks-composition.sh

# Test with verbose output
./scripts/test-eks-composition.sh --verbose

# Test with custom example
./scripts/test-eks-composition.sh --example examples/compute/eks-cluster-comprehensive.yaml
```

**See:** [Testing Script Documentation](/scripts/test-eks-composition.sh)

---

## Troubleshooting

For detailed troubleshooting guidance, see:

**[EKS Composition Troubleshooting Guide](/docs/eks-composition-troubleshooting.md)**

Common issues:
- IAM permission errors
- VPC/subnet misconfigurations
- Node group launch failures
- Add-on compatibility issues
- Connection secret problems

---

## Additional Resources

### Related Documentation

- [EKS Cluster Examples](/examples/compute/)
- [XRD Definition](/infra-definitions/xrds/compute/xrd-eks-cluster.yaml)
- [Portal Kombat Architecture](/docs/ARCHITECTURE.md)
- [CLAUDE.md Development Guide](/CLAUDE.md)

### External Resources

- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [AWS Provider Documentation](https://marketplace.upbound.io/providers/upbound/provider-aws/)

### AWS EKS Add-ons

- [CoreDNS](https://docs.aws.amazon.com/eks/latest/userguide/managing-coredns.html)
- [VPC-CNI](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)
- [kube-proxy](https://docs.aws.amazon.com/eks/latest/userguide/managing-kube-proxy.html)
- [Pod Identity Agent](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [EFS CSI Driver](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)

### IAM and Security

- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [IRSA (IAM Roles for Service Accounts)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)

---

**Last Updated:** 2025-11-09
**Composition Version:** v1alpha1 (production)
**Maintainer:** Portal Kombat Platform Team
