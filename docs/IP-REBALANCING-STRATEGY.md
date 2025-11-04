# IP Allocation Rebalancing Strategy

## Current State Analysis

### Cluster Configuration
- **Cluster Name**: raiden-control-plane
- **EKS Version**: 1.33
- **Node Group**: initial-20251102125824597600000001
- **Capacity Type**: SPOT instances
- **Instance Types**: m5.xlarge, m5.2xlarge
- **Scaling Config**:
  - Min: 1
  - Max: 5
  - Desired: 3 (currently 5 nodes running)

### Current Node Distribution
| Node | AZ | Subnet | ENIs | IPs Used | Pod Count |
|------|-------|---------|------|----------|-----------|
| ip-10-140-59-135 | us-east-2a | 10.140.59.0/24 | 3 | 45 | ~6 |
| ip-10-140-60-118 | us-east-2b | 10.140.60.0/24 | 2 | 30 | ~6 |
| ip-10-140-61-152 | us-east-2c | 10.140.61.0/24 | 3 | 45 | 5 |
| ip-10-140-61-164 | us-east-2c | 10.140.61.0/24 | 3 | 45 | 5 |
| ip-10-140-61-221 | us-east-2c | 10.140.61.0/24 | 4 | 60 | 40 |

**Issue**: 3 of 5 nodes in us-east-2c, causing subnet IP pressure

### Subnet IP Availability
| Subnet | AZ | CIDR | Available IPs | Status |
|--------|-----|------|---------------|--------|
| subnet-0b38b67589017f7e3 | us-east-2a | 10.140.59.0/24 | 198 | ✅ Healthy |
| subnet-091c47ba29231928e | us-east-2b | 10.140.60.0/24 | 215 | ✅ Healthy |
| subnet-051a61728a2e6b2f4 | us-east-2c | 10.140.61.0/24 | 94 | ⚠️ 63% used |

---

## Strategy Options

### Option 1: Scale Down to Desired Capacity (Immediate - Recommended)
**Goal**: Return to desired capacity of 3 nodes and let AWS rebalance naturally

**Current Situation**: You have 5 nodes but desired capacity is 3. Two nodes are likely extras from scaling events.

**Steps**:
```bash
# 1. Identify which nodes to drain (choose 2 from us-east-2c)
kubectl get nodes --show-labels | grep us-east-2c

# 2. Cordon and drain the least utilized nodes first
kubectl cordon ip-10-140-61-152.compute.internal
kubectl cordon ip-10-140-61-164.compute.internal

kubectl drain ip-10-140-61-152.compute.internal --ignore-daemonsets --delete-emptydir-data
kubectl drain ip-10-140-61-164.compute.internal --ignore-daemonsets --delete-emptydir-data

# 3. After pods are rescheduled and healthy, terminate the instances
# AWS ASG will maintain desired capacity of 3 and balance across AZs
export AWS_PROFILE=ims-platform-dev
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name eks-initial-20251102125824597600000001-60cd2252-e02c-9856-af0f-536535ecd450 \
  --desired-capacity 3

# ASG will naturally balance nodes across us-east-2a, us-east-2b, us-east-2c
```

**Expected Result**:
- 1 node in us-east-2a
- 1 node in us-east-2b
- 1 node in us-east-2c
- Subnet pressure relieved in us-east-2c

**Risk**: Low - Returns to intended configuration
**Downtime**: None (pods are drained gracefully)
**Time to Complete**: ~10 minutes

---

### Option 2: Enable AZ Rebalancing in ASG (Long-term)
**Goal**: Ensure AWS automatically balances nodes across AZs as cluster scales

**Current**: ASG has subnets in all 3 AZs but may not be actively rebalancing

**Steps**:
```bash
export AWS_PROFILE=ims-platform-dev

# Enable AZ rebalancing process
aws autoscaling resume-processes \
  --auto-scaling-group-name eks-initial-20251102125824597600000001-60cd2252-e02c-9856-af0f-536535ecd450 \
  --scaling-processes AZRebalance

# Verify AZ rebalancing is active
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-initial-20251102125824597600000001-60cd2252-e02c-9856-af0f-536535ecd450 \
  --query 'AutoScalingGroups[0].SuspendedProcesses'
```

**Expected Result**: Future scaling events will balance nodes across AZs automatically

**Risk**: Very Low - Standard AWS best practice
**Downtime**: None
**Time to Complete**: Immediate (affects future scaling)

---

### Option 3: Use Cluster Autoscaler with AZ-Aware Balancing (Advanced)
**Goal**: Intelligent pod-driven scaling with AZ awareness

**Prerequisites**:
- Cluster Autoscaler must be installed
- IAM permissions for autoscaling

**Check if Cluster Autoscaler is installed**:
```bash
kubectl get deployment cluster-autoscaler -n kube-system
```

**Configuration**:
```yaml
# If not installed, add via Helm or manifest
# Configure with balance-similar-node-groups flag

apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: cluster-autoscaler
        command:
        - ./cluster-autoscaler
        - --balance-similar-node-groups=true
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/raiden-control-plane
```

**Risk**: Medium - Requires additional infrastructure management
**Downtime**: None
**Time to Complete**: 1-2 hours setup

---

### Option 4: Create Separate Node Groups per AZ (Most Control)
**Goal**: Explicit control over node placement per AZ

**Steps**:
```bash
export AWS_PROFILE=ims-platform-dev

# Create 3 separate node groups, one per AZ
aws eks create-nodegroup \
  --cluster-name raiden-control-plane \
  --nodegroup-name nodes-us-east-2a \
  --subnets subnet-0b38b67589017f7e3 \
  --instance-types m5.xlarge m5.2xlarge \
  --scaling-config minSize=1,maxSize=3,desiredSize=1 \
  --capacity-type SPOT \
  --node-role <your-node-role-arn>

aws eks create-nodegroup \
  --cluster-name raiden-control-plane \
  --nodegroup-name nodes-us-east-2b \
  --subnets subnet-091c47ba29231928e \
  --instance-types m5.xlarge m5.2xlarge \
  --scaling-config minSize=1,maxSize=3,desiredSize=1 \
  --capacity-type SPOT \
  --node-role <your-node-role-arn>

aws eks create-nodegroup \
  --cluster-name raiden-control-plane \
  --nodegroup-name nodes-us-east-2c \
  --subnets subnet-051a61728a2e6b2f4 \
  --instance-types m5.xlarge m5.2xlarge \
  --scaling-config minSize=1,maxSize=3,desiredSize=1 \
  --capacity-type SPOT \
  --node-role <your-node-role-arn>

# After new nodes are ready, drain and delete old node group
```

**Benefits**:
- Precise control over AZ distribution
- Can set different scaling policies per AZ
- Easier capacity planning

**Drawbacks**:
- More complex to manage
- Manual intervention for rebalancing
- Three separate autoscaling groups to monitor

**Risk**: Medium - More moving parts
**Downtime**: None (blue/green node group migration)
**Time to Complete**: 2-3 hours

---

## Recommended Implementation Plan

### Phase 1: Immediate Relief (Today)
1. **Scale down to desired capacity (Option 1)**
   - Reduces nodes from 5 to 3
   - Alleviates us-east-2c subnet pressure
   - Returns to intended configuration

### Phase 2: Enable Auto-Rebalancing (This Week)
2. **Enable AZ rebalancing (Option 2)**
   - Ensures future scaling events balance across AZs
   - No operational overhead
   - Standard AWS best practice

### Phase 3: Monitor and Optimize (Ongoing)
3. **Set up monitoring alerts**:
```bash
# Create CloudWatch alarm for subnet IP exhaustion
export AWS_PROFILE=ims-platform-dev

aws cloudwatch put-metric-alarm \
  --alarm-name eks-subnet-us-east-2c-ip-low \
  --alarm-description "Alert when subnet IPs drop below threshold" \
  --metric-name AvailableIpAddressCount \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 50 \
  --comparison-operator LessThanThreshold \
  --dimensions Name=SubnetId,Value=subnet-051a61728a2e6b2f4
```

4. **Consider future subnet strategy**:
   - If cluster grows beyond 10 nodes, evaluate using larger subnets:
     - 100.100.0.0/16 (65k IPs, us-east-2a)
     - 100.101.0.0/16 (65k IPs, us-east-2b)
     - 100.102.0.0/16 (65k IPs, us-east-2c)

---

## Monitoring Commands

### Check Current Distribution
```bash
# View nodes per AZ
kubectl get nodes --label-columns=topology.kubernetes.io/zone

# Count nodes per AZ
kubectl get nodes -o json | jq -r '.items[] | .metadata.labels["topology.kubernetes.io/zone"]' | sort | uniq -c

# Check pod distribution
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | sort | uniq -c
```

### Monitor Subnet IP Usage
```bash
export AWS_PROFILE=ims-platform-dev

# Check all subnet IPs
aws ec2 describe-subnets \
  --subnet-ids subnet-0b38b67589017f7e3 subnet-091c47ba29231928e subnet-051a61728a2e6b2f4 \
  --query 'Subnets[].[SubnetId,AvailabilityZone,CidrBlock,AvailableIpAddressCount]' \
  --output table

# Watch ENI allocation
aws ec2 describe-network-interfaces \
  --filters "Name=subnet-id,Values=subnet-051a61728a2e6b2f4" \
  --query 'length(NetworkInterfaces)'
```

### Check ASG Health
```bash
export AWS_PROFILE=ims-platform-dev

# Current ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-initial-20251102125824597600000001-60cd2252-e02c-9856-af0f-536535ecd450 \
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Current:Instances|length(@),Zones:AvailabilityZones}' \
  --output table

# Instance distribution across AZs
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-initial-20251102125824597600000001-60cd2252-e02c-9856-af0f-536535ecd450 \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,HealthStatus]' \
  --output table
```

---

## Decision Matrix

| Strategy | Effort | Risk | Time | Best For |
|----------|--------|------|------|----------|
| Scale to Desired (Option 1) | Low | Low | 10 min | **Immediate relief** |
| Enable AZ Rebalance (Option 2) | Very Low | Very Low | Immediate | **Long-term stability** |
| Cluster Autoscaler (Option 3) | Medium | Medium | 1-2 hrs | Dynamic workloads |
| Per-AZ Node Groups (Option 4) | High | Medium | 2-3 hrs | Maximum control |

**Recommended**: Start with **Option 1 + Option 2** combination for quick wins with minimal risk.

---

## Post-Implementation Validation

After implementing the strategy, verify success:

```bash
# 1. Check node distribution is balanced
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.labels["topology.kubernetes.io/zone"]): \(.metadata.name)"' | sort

# 2. Verify subnet IP availability improved
export AWS_PROFILE=ims-platform-dev
aws ec2 describe-subnets --subnet-ids subnet-051a61728a2e6b2f4 \
  --query 'Subnets[0].AvailableIpAddressCount'

# 3. Confirm pods are healthy
kubectl get pods -A | grep -v Running | grep -v Completed

# 4. Check ASG is at desired capacity
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names eks-initial-20251102125824597600000001-60cd2252-e02c-9856-af0f-536535ecd450 \
  --query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Current:Instances|length(@)}'
```

---

## Contact and Support

Questions or issues? Check:
- EKS Node Group documentation: https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html
- AWS ASG AZ Rebalancing: https://docs.aws.amazon.com/autoscaling/ec2/userguide/auto-scaling-benefits.html#arch-AutoScalingMultiAZ
- Cluster Autoscaler: https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler
