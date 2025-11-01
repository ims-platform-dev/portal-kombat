# Existing VPC Deployment Guide

This guide explains how to deploy the EKS cluster into an existing VPC infrastructure.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Subnet Requirements](#subnet-requirements)
- [Subnet Tagging](#subnet-tagging)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## Prerequisites

Before deploying EKS into an existing VPC, ensure:

1. **VPC Configuration:**
   - DNS hostnames enabled (`enableDnsHostnames: true`)
   - DNS resolution enabled (`enableDnsSupport: true`)
   - Sufficient CIDR block for EKS nodes and pods

2. **Subnets:**
   - At least 2 private subnets in different Availability Zones (AWS EKS requirement)
   - Each private subnet must have a route to NAT Gateway or VPC endpoints for internet access
   - Sufficient free IP addresses (recommend at least /24 per subnet)
   - Public subnets (optional) for internet-facing load balancers

3. **Networking:**
   - Internet Gateway attached to VPC (for public subnets)
   - NAT Gateway in public subnet with route from private subnets
   - Security groups allowing cluster communication

4. **IAM Permissions:**
   - Terraform execution role must have permissions to create EKS cluster and associated IAM roles
   - Ability to create/modify security groups

## Subnet Requirements

### Minimum Requirements

EKS requires at least **2 private subnets** spanning **2 different Availability Zones**.

Example:
```
VPC: 10.0.0.0/16
├── Private Subnet 1: 10.0.1.0/24 (us-east-1a)
├── Private Subnet 2: 10.0.2.0/24 (us-east-1b)
├── Public Subnet 1:  10.0.101.0/24 (us-east-1a)
└── Public Subnet 2:  10.0.102.0/24 (us-east-1b)
```

### IP Address Planning

Each EKS node requires:
- 1 primary IP for the node
- Additional IPs for pods (depends on CNI configuration)

**Recommendation:**
- Use /24 subnets (254 IPs) for most workloads
- Use /23 subnets (510 IPs) for high-density clusters
- Reserve IPs for future growth

### Internet Connectivity

**Private Subnets** must have internet access for:
- Pulling container images from ECR/DockerHub
- Downloading Kubernetes binaries
- Add-on communication with AWS services

Options:
1. **NAT Gateway** (recommended): Route `0.0.0.0/0` through NAT Gateway in public subnet
2. **VPC Endpoints**: Create VPC endpoints for ECR, S3, and other AWS services (more cost-effective)

## Subnet Tagging

Kubernetes uses specific tags to discover subnets for load balancer provisioning.

### Required Tags

#### Private Subnets (Required)

Private subnets used for EKS worker nodes **must** be tagged with:

```
Key: kubernetes.io/role/internal-elb
Value: 1
```

This tag enables the AWS Load Balancer Controller to create **internal** Application Load Balancers (ALBs) and Network Load Balancers (NLBs).

#### Public Subnets (Optional but Recommended)

Public subnets for internet-facing load balancers **should** be tagged with:

```
Key: kubernetes.io/role/elb
Value: 1
```

This tag enables the AWS Load Balancer Controller to create **internet-facing** ALBs and NLBs.

### Optional Tags

#### Cluster-Specific Tags

If you run multiple EKS clusters in the same VPC with shared subnets:

```
Key: kubernetes.io/cluster/<cluster-name>
Value: shared
```

Replace `<cluster-name>` with your actual cluster name.

#### Subnet Identification

For better organization:

```
Key: Name
Value: <descriptive-name>
```

Example: `eks-private-subnet-us-east-1a`

## Tagging Subnets

### Using AWS CLI

#### 1. List Your Subnets

```bash
# List all subnets in your VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-1234567890abcdef0" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key==`Name`].Value|[0]]' \
  --output table \
  --region us-east-1
```

#### 2. Tag Private Subnets

```bash
# Tag a single private subnet
aws ec2 create-tags \
  --resources subnet-0a1b2c3d4e5f6g7h8 \
  --tags Key=kubernetes.io/role/internal-elb,Value=1 \
  --region us-east-1

# Tag multiple private subnets at once
aws ec2 create-tags \
  --resources subnet-0a1b2c3d4e5f6g7h8 subnet-1a2b3c4d5e6f7g8h9 \
  --tags Key=kubernetes.io/role/internal-elb,Value=1 \
  --region us-east-1
```

#### 3. Tag Public Subnets

```bash
# Tag a single public subnet
aws ec2 create-tags \
  --resources subnet-3b4c5d6e7f8g9h0i1 \
  --tags Key=kubernetes.io/role/elb,Value=1 \
  --region us-east-1

# Tag multiple public subnets at once
aws ec2 create-tags \
  --resources subnet-3b4c5d6e7f8g9h0i1 subnet-4c5d6e7f8g9h0i1j2 \
  --tags Key=kubernetes.io/role/elb,Value=1 \
  --region us-east-1
```

#### 4. Add Cluster-Specific Tags (Optional)

```bash
# Add cluster tag to subnets
aws ec2 create-tags \
  --resources subnet-0a1b2c3d4e5f6g7h8 subnet-1a2b3c4d5e6f7g8h9 \
  --tags Key=kubernetes.io/cluster/crossplane-blueprints,Value=shared \
  --region us-east-1
```

#### 5. Verify Tags

```bash
# Verify tags on a subnet
aws ec2 describe-subnets \
  --subnet-ids subnet-0a1b2c3d4e5f6g7h8 \
  --query 'Subnets[*].Tags' \
  --region us-east-1

# Verify all subnets with Kubernetes tags in your VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-1234567890abcdef0" \
            "Name=tag-key,Values=kubernetes.io/role/*" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`kubernetes.io/role/internal-elb`].Value|[0],Tags[?Key==`kubernetes.io/role/elb`].Value|[0]]' \
  --output table \
  --region us-east-1
```

### Using Terraform

If you manage your VPC with Terraform, add tags to your subnet resources:

```hcl
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "private-subnet-${count.index + 1}"
    "kubernetes.io/role/internal-elb"          = "1"
    "kubernetes.io/cluster/crossplane-blueprints" = "shared"
  }
}

resource "aws_subnet" "public" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 100)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "public-subnet-${count.index + 1}"
    "kubernetes.io/role/elb"                   = "1"
    "kubernetes.io/cluster/crossplane-blueprints" = "shared"
  }
}
```

### Using AWS Console

1. Navigate to **VPC Dashboard** → **Subnets**
2. Select the subnet you want to tag
3. Click **Tags** tab
4. Click **Manage tags**
5. Add tag:
   - **Key**: `kubernetes.io/role/internal-elb` (for private) or `kubernetes.io/role/elb` (for public)
   - **Value**: `1`
6. Click **Save**

## Configuration

### 1. Identify Your Resources

```bash
# Get your VPC ID
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=my-vpc-name" \
  --query 'Vpcs[0].VpcId' --output text --region us-east-1

# Get private subnet IDs
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
            "Name=tag:Name,Values=*private*" \
  --query 'Subnets[*].SubnetId' --output text --region us-east-1

# Get public subnet IDs
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
            "Name=tag:Name,Values=*public*" \
  --query 'Subnets[*].SubnetId' --output text --region us-east-1
```

### 2. Create Configuration File

Create `terraform.tfvars`:

```hcl
region             = "us-east-1"
name               = "crossplane-blueprints"
create_vpc         = false
vpc_id             = "vpc-1234567890abcdef0"
private_subnet_ids = ["subnet-0a1b2c3d", "subnet-1a2b3c4d"]
public_subnet_ids  = ["subnet-3b4c5d6e", "subnet-4c5d6e7f"]
cluster_version    = "1.29"
```

Or use the provided example:

```bash
cp examples/existing-vpc.tfvars terraform.tfvars
# Edit terraform.tfvars with your actual IDs
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

## Validation Checklist

Before deploying, verify:

- [ ] VPC has DNS hostnames and DNS support enabled
- [ ] At least 2 private subnets in different AZs
- [ ] Private subnets tagged with `kubernetes.io/role/internal-elb=1`
- [ ] Public subnets tagged with `kubernetes.io/role/elb=1` (if using)
- [ ] Private subnets have route to NAT Gateway or VPC endpoints
- [ ] Sufficient free IPs in subnets
- [ ] Security groups allow necessary traffic
- [ ] Subnet IDs are correct in configuration file

## Troubleshooting

### Load Balancers Not Provisioning

**Symptom**: Service with `type: LoadBalancer` stays in Pending state

**Causes**:
1. Missing subnet tags
2. Subnets in only one AZ
3. Insufficient permissions for AWS Load Balancer Controller

**Solution**:
```bash
# Verify subnet tags
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check subnets have correct tags
aws ec2 describe-subnets --subnet-ids subnet-xxxxx \
  --query 'Subnets[*].Tags' --region us-east-1

# Re-tag if necessary
aws ec2 create-tags --resources subnet-xxxxx \
  --tags Key=kubernetes.io/role/internal-elb,Value=1
```

### Nodes Not Joining Cluster

**Symptom**: Nodes stuck in NotReady state or not appearing

**Causes**:
1. No internet access from private subnets
2. Security group blocking communication
3. Incorrect subnet IDs

**Solution**:
```bash
# Verify route table has NAT Gateway route
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx" \
  --query 'RouteTables[*].Routes' --region us-east-1

# Should see route: 0.0.0.0/0 → nat-xxxxx

# Check security groups
kubectl get nodes
aws eks describe-cluster --name crossplane-blueprints \
  --query 'cluster.resourcesVpcConfig.securityGroupIds'
```

### Insufficient IP Addresses

**Symptom**: Pods stuck in Pending state, events show "too many pods"

**Causes**:
1. Subnet CIDR too small
2. Too many pods scheduled per node

**Solution**:
```bash
# Check available IPs in subnet
aws ec2 describe-subnets --subnet-ids subnet-xxxxx \
  --query 'Subnets[*].AvailableIpAddressCount' --region us-east-1

# Consider:
# - Using larger subnet CIDR blocks (/23 instead of /24)
# - Reducing pods per node
# - Adding more subnets
```

### Validation Errors During Plan

**Symptom**: Terraform validation errors about missing variables

**Causes**:
1. `vpc_id` not provided when `create_vpc = false`
2. Less than 2 private subnets provided
3. Variable type mismatch

**Solution**:
```bash
# Verify your tfvars file
cat terraform.tfvars

# Ensure proper list format for subnets
private_subnet_ids = ["subnet-xxx", "subnet-yyy"]  # Correct
private_subnet_ids = "subnet-xxx,subnet-yyy"       # Wrong
```

## AWS EKS Networking Best Practices

1. **Use Multiple AZs**: Always span at least 2 AZs for high availability
2. **Separate Subnets**: Use dedicated subnets for EKS, don't share with other workloads
3. **Plan IP Space**: Reserve adequate IPs for cluster growth
4. **NAT Gateway HA**: Use NAT Gateway per AZ for production (costs more but more resilient)
5. **VPC Endpoints**: Consider VPC endpoints for ECR, S3 to reduce NAT costs
6. **Network Policies**: Implement network policies for pod-to-pod communication control
7. **Security Groups**: Use separate security groups for control plane and nodes

## References

- [AWS EKS Cluster VPC Considerations](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [AWS Load Balancer Controller - Subnet Discovery](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.4/deploy/subnet_discovery/)
- [EKS Best Practices Guide - Networking](https://aws.github.io/aws-eks-best-practices/networking/)
- [Kubernetes Service Types](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)
