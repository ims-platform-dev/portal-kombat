# EKS Composition Troubleshooting Guide

This guide provides comprehensive troubleshooting steps for the Portal Kombat EKS production composition.

## Table of Contents

- [Debugging Workflow](#debugging-workflow)
- [Common Failure Scenarios](#common-failure-scenarios)
- [AWS CLI Validation](#aws-cli-validation)
- [Recovery Procedures](#recovery-procedures)
- [Known Issues](#known-issues)
- [Additional Resources](#additional-resources)

---

## Debugging Workflow

Follow this systematic approach when troubleshooting EKS cluster issues:

### 1. Check Cluster Claim Status

```bash
# Get high-level status
kubectl get ekscluster my-cluster

# Expected output when healthy:
# NAME         READY   SYNCED   AGE
# my-cluster   True    True     15m

# Get detailed status with conditions
kubectl describe ekscluster my-cluster

# Check status conditions
kubectl get ekscluster my-cluster -o jsonpath='{.status.conditions}' | jq
```

**Key Status Fields:**
- `READY=True`: All resources are ready and healthy
- `SYNCED=True`: Composition has been applied successfully
- `conditions`: Detailed status messages

### 2. Check Composite Resource (XR)

```bash
# Get the composite resource name
kubectl get ekscluster my-cluster -o jsonpath='{.spec.resourceRef.name}'

# Describe the composite resource
kubectl describe xekscluster <xr-name>

# Check composite resource status
kubectl get xekscluster <xr-name> -o yaml
```

### 3. List All Managed Resources

```bash
# List all managed resources created by the composition
kubectl get managed -l crossplane.io/composite=<xr-name>

# Check for resources in non-ready state
kubectl get managed -l crossplane.io/composite=<xr-name> | grep -v True

# Get detailed info on specific resource
kubectl describe <resource-type> <resource-name>
```

### 4. Check Provider Logs

```bash
# Check Crossplane core logs
kubectl logs -n crossplane-system -l app=crossplane --tail=100

# Check AWS provider logs (EKS resources)
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-eks --tail=100

# Check AWS provider logs (IAM resources)
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-iam --tail=100

# Check AWS provider logs (EC2 resources)
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=100

# Follow logs in real-time
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-eks -f
```

### 5. Check Events

```bash
# Get recent events for the cluster
kubectl get events --field-selector involvedObject.name=my-cluster --sort-by='.lastTimestamp'

# Get events in crossplane-system namespace
kubectl get events -n crossplane-system --sort-by='.lastTimestamp' | tail -20

# Watch events in real-time
kubectl get events -n crossplane-system --watch
```

### 6. Validate Connection Secret

```bash
# Check if connection secret was created
kubectl get secret my-cluster-connection -n default

# Verify secret contains expected keys
kubectl get secret my-cluster-connection -n default -o jsonpath='{.data}' | jq 'keys'

# Expected keys:
# - kubeconfig
# - endpoint
# - ca-certificate-authority-data
# - oidc-issuer-url
# - cluster-name
# - region

# Extract and decode kubeconfig
kubectl get secret my-cluster-connection -n default \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/cluster-kubeconfig

# Test cluster access
KUBECONFIG=/tmp/cluster-kubeconfig kubectl get nodes
```

---

## Common Failure Scenarios

### 1. IAM Permission Errors

**Symptoms:**
- Resources stuck in "Creating" state
- Provider logs show `AccessDenied` or `UnauthorizedOperation` errors
- Status message: "cannot create resource: AccessDeniedException"

**Diagnosis:**

```bash
# Check provider configuration
kubectl get providerconfig default -o yaml

# Check provider logs for IAM errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-iam --tail=50 | grep -i denied

# Common error messages:
# - "User: arn:aws:sts::123456789012:assumed-role/crossplane-sa-role is not authorized to perform: eks:CreateCluster"
# - "User is not authorized to perform: iam:CreateRole"
```

**Solution:**

1. Verify the Crossplane service account IAM role has required permissions:

```bash
# Get the IAM role ARN from provider config
kubectl get providerconfig default -o jsonpath='{.spec.assumeRoleARN}'

# Check IAM role policies in AWS
aws iam list-attached-role-policies --role-name crossplane-sa-role
aws iam list-role-policies --role-name crossplane-sa-role
```

2. Required IAM permissions for EKS composition:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:*",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:TagRole",
        "ec2:CreateLaunchTemplate",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSubnets",
        "ec2:DescribeVpcs",
        "ec2:DescribeSecurityGroups"
      ],
      "Resource": "*"
    }
  ]
}
```

3. Update IAM policy and wait for Crossplane to retry (automatic retry every 1 minute).

**See also:** `/shared/managed-resources/iam-roles/iam-policies/SETUP-INSTRUCTIONS.md`

---

### 2. VPC/Subnet Issues

**Symptoms:**
- EKS cluster creation fails with "InvalidSubnetId" or "InvalidVpcId"
- Provider logs show: "The subnet ID 'subnet-xxx' does not exist"
- Status message: "InvalidParameterException: Subnets specified in configuration are not valid"

**Diagnosis:**

```bash
# Check the VPC and subnet IDs in the claim
kubectl get ekscluster my-cluster -o jsonpath='{.spec.parameters.vpcConfig}'

# Verify subnets exist and are in correct region
aws ec2 describe-subnets --subnet-ids subnet-xxx --region us-east-2

# Check subnet availability zones
aws ec2 describe-subnets --subnet-ids subnet-aaa subnet-bbb --region us-east-2 \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,VpcId]' --output table
```

**Common Issues:**
- Subnets are in a different AWS region than specified in claim
- Subnets belong to different VPCs
- Less than 2 subnets provided (minimum required)
- Subnets are not in multiple availability zones (recommended for HA)

**Solution:**

1. Verify VPC and subnet configuration:

```bash
# List all subnets in VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-xxx" --region us-east-2 \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,Tags[?Key==`Name`].Value|[0]]' --output table

# Ensure subnets are private (no direct internet gateway route)
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-xxx" --region us-east-2
```

2. Update the EKSCluster claim with correct subnet IDs:

```yaml
spec:
  parameters:
    vpcConfig:
      vpcId: vpc-0123456789abcdef0  # Correct VPC ID
      subnetIds:
        - subnet-0aaaaaaaaaaaaaaaa  # Private subnet in AZ-1
        - subnet-0bbbbbbbbbbbbbbb   # Private subnet in AZ-2
        - subnet-0ccccccccccccccc   # Private subnet in AZ-3
```

3. Apply the updated claim:

```bash
kubectl apply -f my-cluster.yaml
```

---

### 3. Node Group Launch Failures

**Symptoms:**
- EKS cluster is ready, but node group shows "Degraded" or "CreateFailed"
- Nodes fail to join the cluster
- Provider logs show launch template or scaling errors
- Status message: "NodeCreationFailure: Instances failed to join the cluster"

**Diagnosis:**

```bash
# Check node group status
kubectl describe nodegroup <nodegroup-name>

# Check launch template
kubectl describe launchtemplate <launchtemplate-name>

# Get node group status from AWS
aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-default-nodes-0 \
  --region us-east-2 \
  --query 'nodegroup.health'
```

**Common Issues:**
- Launch template references invalid AMI ID
- Instance type not available in selected availability zones
- Security group blocks required traffic
- IAM instance profile missing or misconfigured
- Insufficient subnet IP addresses

**Solution:**

1. Check node group health in AWS console:

```bash
aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-default-nodes-0 \
  --region us-east-2
```

2. Check Auto Scaling Group events:

```bash
# Get ASG name
ASG_NAME=$(aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-default-nodes-0 \
  --region us-east-2 \
  --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)

# Get ASG activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name "${ASG_NAME}" \
  --max-records 10 \
  --region us-east-2
```

3. Check EC2 launch errors:

```bash
# Check for failed EC2 instances
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=my-cluster" \
            "Name=instance-state-name,Values=terminated" \
  --region us-east-2 \
  --query 'Reservations[*].Instances[*].[InstanceId,StateReason.Message]' --output table
```

4. Verify node IAM role has required policies:

```bash
# Check node role policies
kubectl get role -l portal-kombat.io/eks-component=node-role -o jsonpath='{.items[0].metadata.name}'

kubectl describe role <node-role-name>

# Required policies:
# - AmazonEKSWorkerNodePolicy
# - AmazonEC2ContainerRegistryReadOnly
# - AmazonEKS_CNI_Policy
```

5. If using custom networking, verify ENI configuration:

```bash
# Check available IPs in subnets
aws ec2 describe-subnets --subnet-ids subnet-xxx --region us-east-2 \
  --query 'Subnets[*].[SubnetId,AvailableIpAddressCount]' --output table
```

---

### 4. Add-on Failures

**Symptoms:**
- Core cluster add-ons (coredns, vpc-cni, kube-proxy) show "Degraded" state
- Pods fail to schedule or have network connectivity issues
- Add-on version incompatible with cluster version

**Diagnosis:**

```bash
# Check add-on status
kubectl get addon -l crossplane.io/composite=<xr-name>

# Describe specific add-on
kubectl describe addon <addon-name>

# Check add-on status in AWS
aws eks describe-addon \
  --cluster-name my-cluster \
  --addon-name vpc-cni \
  --region us-east-2
```

**Common Issues:**
- Add-on version incompatible with Kubernetes version
- Add-on conflicts with existing installation
- IAM permissions missing for add-on (e.g., EFS CSI driver)

**Solution:**

1. List compatible add-on versions:

```bash
aws eks describe-addon-versions \
  --kubernetes-version 1.32 \
  --addon-name vpc-cni \
  --region us-east-2 \
  --query 'addons[*].addonVersions[*].addonVersion'
```

2. Check add-on health in cluster:

```bash
# Extract kubeconfig
kubectl get secret my-cluster-connection -n default \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/kubeconfig

# Check CoreDNS
KUBECONFIG=/tmp/kubeconfig kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check VPC-CNI
KUBECONFIG=/tmp/kubeconfig kubectl get pods -n kube-system -l k8s-app=aws-node

# Check kube-proxy
KUBECONFIG=/tmp/kubeconfig kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

3. Update add-on version in composition or use `resolveConflicts: OVERWRITE`:

```yaml
clusterAddons:
  coredns:
    enabled: true
    version: "v1.11.1-eksbuild.9"  # Compatible version
    resolveConflicts: OVERWRITE    # Force update
```

4. For EFS CSI driver issues, verify IAM permissions:

```bash
# Check Pod Identity association
aws eks list-pod-identity-associations \
  --cluster-name my-cluster \
  --region us-east-2

# Verify EFS CSI driver role has required policy
aws iam get-role --role-name my-cluster-efs-csi-role
aws iam list-attached-role-policies --role-name my-cluster-efs-csi-role
```

---

### 5. Connection Secret Issues

**Symptoms:**
- Connection secret not created
- Kubeconfig in secret is invalid or cannot authenticate
- Secret missing required keys

**Diagnosis:**

```bash
# Check if secret exists
kubectl get secret my-cluster-connection -n default

# If secret doesn't exist, check cluster status
kubectl describe ekscluster my-cluster

# Verify secret has all required keys
kubectl get secret my-cluster-connection -n default -o jsonpath='{.data}' | jq 'keys'

# Expected keys: kubeconfig, endpoint, ca-certificate-authority-data, oidc-issuer-url, cluster-name, region

# Decode and inspect kubeconfig
kubectl get secret my-cluster-connection -n default \
  -o jsonpath='{.data.kubeconfig}' | base64 -d | head -20
```

**Common Issues:**
- Cluster not fully ready (secret created after cluster becomes active)
- XRD missing `connectionSecretKeys` definition
- Composition not configured to publish connection details
- Secret namespace doesn't exist

**Solution:**

1. Verify XRD defines connection secret keys:

```bash
kubectl get xrd xeksclusters.aws.plt.intelerad.io -o jsonpath='{.spec.connectionSecretKeys}'

# Expected output:
# ["kubeconfig","endpoint","ca-certificate-authority-data","oidc-issuer-url","cluster-name","region"]
```

2. Wait for cluster to become fully active:

```bash
kubectl wait --for=condition=Ready ekscluster/my-cluster --timeout=20m
```

3. Check if namespace exists:

```bash
kubectl get namespace default
```

4. If secret still missing, check Crossplane logs:

```bash
kubectl logs -n crossplane-system -l app=crossplane --tail=100 | grep -i "connection secret"
```

5. Test kubeconfig manually:

```bash
# Extract kubeconfig
kubectl get secret my-cluster-connection -n default \
  -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/test-kubeconfig

# Test authentication
KUBECONFIG=/tmp/test-kubeconfig kubectl get nodes

# If authentication fails, check IAM permissions
KUBECONFIG=/tmp/test-kubeconfig kubectl auth can-i get nodes
```

---

### 6. EFS Mount Target Failures

**Symptoms:**
- EFS CSI driver enabled but EFS file systems cannot be mounted
- Pod mount errors: "Failed to resolve server ..."
- EFS mount targets not created in all availability zones

**Diagnosis:**

```bash
# Check if EFS CSI driver is enabled
kubectl get ekscluster my-cluster -o jsonpath='{.spec.parameters.clusterAddons.awsEfsCsiDriver.enabled}'

# Check EFS CSI driver pods
KUBECONFIG=/tmp/kubeconfig kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-efs-csi-driver

# Check EFS CSI driver add-on status
aws eks describe-addon \
  --cluster-name my-cluster \
  --addon-name aws-efs-csi-driver \
  --region us-east-2

# Check Pod Identity role for EFS CSI driver
kubectl get role -l portal-kombat.io/eks-component=pod-identity-efs-csi
```

**Common Issues:**
- EFS CSI driver IAM role missing `AmazonEFSCSIDriverPolicy`
- Security groups block NFS traffic (port 2049)
- EFS mount targets not in correct subnets
- EFS file system not created

**Solution:**

1. Verify EFS CSI driver IAM permissions:

```bash
# Get the EFS CSI driver Pod Identity role
ROLE_ARN=$(aws eks list-pod-identity-associations \
  --cluster-name my-cluster \
  --region us-east-2 \
  --query 'associations[?namespace==`kube-system`].roleArn' --output text)

# Check attached policies
aws iam list-attached-role-policies --role-name <role-name>

# Should include: AmazonEFSCSIDriverPolicy
```

2. Check security group rules:

```bash
# Get cluster security group
CLUSTER_SG=$(aws eks describe-cluster \
  --name my-cluster \
  --region us-east-2 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

# Verify NFS (port 2049) is allowed
aws ec2 describe-security-groups \
  --group-ids "${CLUSTER_SG}" \
  --region us-east-2 \
  --query 'SecurityGroups[*].IpPermissions[?ToPort==`2049`]'
```

3. Test EFS mounting with a test pod:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: efs-test
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: efs-test-pod
spec:
  containers:
    - name: app
      image: busybox
      command: ["/bin/sh"]
      args: ["-c", "touch /data/test && ls -l /data"]
      volumeMounts:
        - name: efs-storage
          mountPath: /data
  volumes:
    - name: efs-storage
      persistentVolumeClaim:
        claimName: efs-test
```

---

## AWS CLI Validation

Use these AWS CLI commands to verify resources were created correctly:

### Verify EKS Cluster

```bash
# Get cluster status
aws eks describe-cluster \
  --name my-cluster \
  --region us-east-2 \
  --query 'cluster.{Name:name,Status:status,Endpoint:endpoint,Version:version}'

# Check OIDC provider (for IRSA)
aws eks describe-cluster \
  --name my-cluster \
  --region us-east-2 \
  --query 'cluster.identity.oidc.issuer'

# List cluster add-ons
aws eks list-addons \
  --cluster-name my-cluster \
  --region us-east-2

# Check access entries (new authentication mode)
aws eks list-access-entries \
  --cluster-name my-cluster \
  --region us-east-2
```

### Verify Node Groups

```bash
# List node groups
aws eks list-nodegroups \
  --cluster-name my-cluster \
  --region us-east-2

# Describe node group
aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-default-nodes-0 \
  --region us-east-2

# Check node group scaling configuration
aws eks describe-nodegroup \
  --cluster-name my-cluster \
  --nodegroup-name my-cluster-default-nodes-0 \
  --region us-east-2 \
  --query 'nodegroup.scalingConfig'
```

### Verify IAM Roles

```bash
# List IAM roles with cluster name tag
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `my-cluster`)].[RoleName,Arn]' \
  --output table

# Get cluster role details
aws iam get-role --role-name my-cluster-cluster-role

# List attached policies
aws iam list-attached-role-policies --role-name my-cluster-cluster-role

# Get node role details
aws iam get-role --role-name my-cluster-node-role

# List attached policies for node role
aws iam list-attached-role-policies --role-name my-cluster-node-role
```

### Verify Launch Templates

```bash
# List launch templates
aws ec2 describe-launch-templates \
  --filters "Name=tag:ClusterName,Values=my-cluster" \
  --region us-east-2 \
  --query 'LaunchTemplates[*].[LaunchTemplateName,LaunchTemplateId,LatestVersionNumber]' \
  --output table

# Get launch template version details
aws ec2 describe-launch-template-versions \
  --launch-template-id lt-xxx \
  --region us-east-2 \
  --query 'LaunchTemplateVersions[0].LaunchTemplateData'
```

### Verify Pod Identity Associations

```bash
# List Pod Identity associations
aws eks list-pod-identity-associations \
  --cluster-name my-cluster \
  --region us-east-2

# Describe specific association
aws eks describe-pod-identity-association \
  --cluster-name my-cluster \
  --association-id a-xxx \
  --region us-east-2
```

### Verify Security Groups

```bash
# Get cluster security group
aws eks describe-cluster \
  --name my-cluster \
  --region us-east-2 \
  --query 'cluster.resourcesVpcConfig.{ClusterSG:clusterSecurityGroupId,AdditionalSGs:securityGroupIds}'

# Describe security group rules
aws ec2 describe-security-groups \
  --group-ids sg-xxx \
  --region us-east-2
```

### Verify CloudWatch Logging

```bash
# Check enabled log types
aws eks describe-cluster \
  --name my-cluster \
  --region us-east-2 \
  --query 'cluster.logging.clusterLogging[0].types'

# View logs (if enabled)
aws logs tail /aws/eks/my-cluster/cluster --follow
```

---

## Recovery Procedures

### Procedure 1: Force Composition Re-sync

If resources are out of sync or stuck:

```bash
# Annotate claim to trigger reconciliation
kubectl annotate ekscluster my-cluster crossplane.io/paused=false --overwrite

# Force re-sync by updating a non-impactful field
kubectl patch ekscluster my-cluster --type merge -p '{"spec":{"parameters":{"tags":{"LastSync":"'$(date +%s)'"}}}}'
```

### Procedure 2: Delete and Recreate Stuck Resources

If specific managed resources are stuck:

```bash
# Identify stuck resource
kubectl get managed -l crossplane.io/composite=<xr-name> | grep False

# Delete the managed resource (will be recreated)
kubectl delete <resource-type> <resource-name>

# Monitor recreation
kubectl get <resource-type> <resource-name> -w
```

### Procedure 3: Clean Cluster Deletion

To properly delete a cluster and all resources:

```bash
# Step 1: Delete any workloads running on the cluster
# (Load balancers, EBS volumes, etc.)

# Step 2: Delete the cluster claim
kubectl delete ekscluster my-cluster

# Step 3: Monitor deletion progress
kubectl get managed -l crossplane.io/composite=<xr-name> -w

# Step 4: If resources are stuck in deletion, check for finalizers
kubectl get managed -l crossplane.io/composite=<xr-name> -o json | \
  jq '.items[] | select(.metadata.deletionTimestamp != null) | {name: .metadata.name, kind: .kind, finalizers: .metadata.finalizers}'

# Step 5: Force remove finalizers if necessary (use with caution)
kubectl patch <resource-type> <resource-name> --type json \
  -p='[{"op": "remove", "path": "/metadata/finalizers"}]'
```

### Procedure 4: Fix Missing Connection Secret

If connection secret is missing but cluster is ready:

```bash
# Check cluster status
kubectl get ekscluster my-cluster -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'

# If Ready=True but secret missing, check connection secret reference
kubectl get ekscluster my-cluster -o jsonpath='{.spec.writeConnectionSecretToRef}'

# Manually trigger secret creation by patching the claim
kubectl patch ekscluster my-cluster --type merge -p '{"spec":{"writeConnectionSecretToRef":{"name":"my-cluster-connection","namespace":"default"}}}'

# Verify secret is created
kubectl get secret my-cluster-connection -n default
```

---

## Known Issues

### Issue 1: Node Group Array Limitation (Single Node Group Only)

**Problem:** The composition currently supports only ONE node group due to Crossplane function-patch-and-transform limitations with array expansion.

**Workaround:** Use cluster autoscaling and diverse instance types in a single node group, or manually create additional node groups outside Crossplane.

**Planned Fix:** Migration to function-go-templating for native array iteration support (future enhancement).

**See:** `infra-definitions/compositions/compute/README-eks-production.md` for details.

### Issue 2: EFS CSI Driver Requires Manual Security Group Configuration

**Problem:** EFS CSI driver may fail to mount EFS file systems if security groups don't allow NFS traffic.

**Workaround:** Manually add NFS (port 2049) ingress rule to cluster security group:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 2049 \
  --source-group sg-xxx \
  --region us-east-2
```

**Planned Fix:** Add security group rule resource to composition (future enhancement).

### Issue 3: Add-on Version Compatibility

**Problem:** Add-on versions must be compatible with Kubernetes version, but composition uses defaults which may become outdated.

**Workaround:** Explicitly specify add-on versions in claim:

```yaml
clusterAddons:
  coredns:
    enabled: true
    version: "v1.11.1-eksbuild.9"
  vpcCni:
    enabled: true
    version: "v1.18.1-eksbuild.3"
```

**Recommendation:** Regularly update default add-on versions in composition.

### Issue 4: Slow Cluster Creation (10-15 minutes)

**Problem:** EKS cluster creation takes 10-15 minutes, which is expected AWS behavior.

**Not a bug:** This is normal for EKS cluster provisioning. Be patient.

**Monitor progress:**

```bash
kubectl get ekscluster my-cluster -w
aws eks describe-cluster --name my-cluster --region us-east-2 --query 'cluster.status'
```

---

## Additional Resources

### Official Documentation

- [AWS EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [AWS Provider Documentation](https://marketplace.upbound.io/providers/upbound/provider-aws/)
- [EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)

### Related Portal Kombat Documentation

- [EKS Composition README](/infra-definitions/compositions/compute/README-eks-production.md)
- [EKS Cluster Examples](/examples/compute/)
- [Quick Start Guide](/docs/QUICK-START.md)
- [Architecture Overview](/docs/ARCHITECTURE.md)
- [CLAUDE.md](/CLAUDE.md) - Portal Kombat development guide

### Crossplane Debugging Resources

- [Crossplane Debugging Guide](https://docs.crossplane.io/knowledge-base/guides/troubleshoot/)
- [Provider AWS Troubleshooting](https://marketplace.upbound.io/providers/upbound/provider-aws/latest/docs/troubleshooting)

### AWS CLI Reference

- [EKS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/eks/)
- [IAM CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/iam/)
- [EC2 CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/ec2/)

---

## Getting Help

If you encounter issues not covered in this guide:

1. Check Crossplane provider logs for detailed error messages
2. Review AWS CloudTrail for API call failures
3. Search existing GitHub issues in the Portal Kombat repository
4. Consult AWS EKS documentation for service-specific limitations
5. Reach out to the platform team for assistance

---

**Last Updated:** 2025-11-09
**Composition Version:** v1alpha1 (production)
