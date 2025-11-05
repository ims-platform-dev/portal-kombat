# AWS EBS CSI Driver - Persistent Storage for EKS

This directory configures the AWS EBS CSI Driver for persistent block storage in the dev EKS cluster.

## Overview

The AWS EBS Container Storage Interface (CSI) Driver enables EKS pods to use Amazon EBS volumes for persistent storage. This replaces the legacy in-tree Kubernetes EBS provisioner with a modern, actively maintained solution.

## Architecture

```
Pod → PVC → StorageClass → EBS CSI Driver → AWS EBS Volume
```

**Components:**
- **Controller**: Manages volume provisioning, attachment, snapshots (runs as Deployment)
- **Node DaemonSet**: Handles volume mounting on worker nodes
- **StorageClasses**: Define volume types and policies

## Storage Classes

### gp3 (Default) ✅
**Use for**: 99% of workloads in dev
- **Type**: General Purpose SSD (gp3)
- **Performance**: 3,000 IOPS, 125 MB/s throughput (baseline)
- **Cost**: ~$0.08/GB-month
- **Reclaim Policy**: Delete (volumes deleted when PVC is deleted)
- **Expansion**: Enabled (resize without downtime)
- **Encryption**: Enabled by default

**Best for:**
- Prometheus/Grafana metrics storage
- Application caches
- Development databases
- Log storage

**Example PVC:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
```

### gp3-retain
**Use for**: Data that should survive pod deletion
- Same as `gp3` but with **Retain** reclaim policy
- Volume persists after PVC deletion (requires manual cleanup)
- Good for development databases you want to preserve

**Example:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-dev-data
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3-retain
  resources:
    requests:
      storage: 20Gi
```

### io2 (High Performance)
**Use for**: Production-like database testing
- **Type**: Provisioned IOPS SSD (io2)
- **Performance**: 10,000 IOPS (guaranteed, configurable)
- **Cost**: ~$0.125/GB-month + $0.065/IOPS-month (**expensive**)
- **Reclaim Policy**: Delete
- **Use sparingly in dev environment**

**Best for:**
- High-throughput database testing
- Performance benchmarking
- Production simulation

## IAM Setup

The EBS CSI Driver requires AWS permissions via IRSA (IAM Roles for Service Accounts).

### 1. Create IAM Policy

```bash
# From repository root
aws iam create-policy \
  --policy-name AmazonEKS_EBS_CSI_Driver_Policy \
  --policy-document file://environments/dev/cluster-addons/ebs-csi-driver/iam-policy.json
```

### 2. Create IAM Role with IRSA

```bash
# Replace with your values
CLUSTER_NAME="your-eks-cluster"
AWS_ACCOUNT_ID="123456789012"
AWS_REGION="us-east-2"

# Create IAM role and associate with ServiceAccount
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=ebs-csi-controller-sa \
  --attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AmazonEKS_EBS_CSI_Driver_Policy \
  --approve \
  --region=$AWS_REGION
```

### 3. Update values.yaml

Update the IAM role ARN in `values.yaml`:

```yaml
aws-ebs-csi-driver:
  controller:
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: "arn:aws:iam::YOUR_ACCOUNT_ID:role/ebs-csi-driver-role"
```

## Deployment

The EBS CSI Driver is deployed via ArgoCD as part of the platform services:

```bash
# Sync via ArgoCD (automatic)
kubectl get application dev-k8s-ebs-csi-driver -n argocd

# Or apply directly for testing
helm dependency build environments/dev/cluster-addons/ebs-csi-driver
helm install ebs-csi-driver environments/dev/cluster-addons/ebs-csi-driver \
  --namespace kube-system
```

## Verification

### Check Driver Installation

```bash
# Check controller pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check node DaemonSet
kubectl get daemonset -n kube-system ebs-csi-node

# Check StorageClasses
kubectl get storageclass
```

### Test Storage

Create a test PVC:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-ebs-claim
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 4Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-ebs-pod
spec:
  containers:
    - name: app
      image: centos:latest
      command: ["/bin/sh"]
      args: ["-c", "while true; do echo $(date -u) >> /data/out.txt; sleep 5; done"]
      volumeMounts:
        - name: persistent-storage
          mountPath: /data
  volumes:
    - name: persistent-storage
      persistentVolumeClaim:
        claimName: test-ebs-claim
EOF

# Verify PVC is bound
kubectl get pvc test-ebs-claim

# Check data is being written
kubectl exec test-ebs-pod -- cat /data/out.txt

# Cleanup
kubectl delete pod test-ebs-pod
kubectl delete pvc test-ebs-claim
```

## Volume Operations

### Resize Volume

Volumes using storage classes with `allowVolumeExpansion: true` can be resized:

```bash
# Edit PVC to increase size
kubectl patch pvc prometheus-data -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# Resize happens automatically (may require pod restart)
kubectl rollout restart statefulset prometheus
```

### Create Snapshot

```bash
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: prometheus-snapshot
spec:
  volumeSnapshotClassName: csi-aws-vss
  source:
    persistentVolumeClaimName: prometheus-data
EOF

# Check snapshot status
kubectl get volumesnapshot prometheus-snapshot
```

### Restore from Snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prometheus-data-restored
spec:
  dataSource:
    name: prometheus-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 50Gi
```

## Troubleshooting

### PVC Stuck in Pending

**Symptoms**: PVC remains in `Pending` state

**Causes**:
1. **No node available**: Volume binding waits for pod to be scheduled
2. **IAM permissions**: EBS CSI driver can't create volumes
3. **Quota exceeded**: AWS EBS volume limit reached

**Debug**:
```bash
# Check PVC events
kubectl describe pvc <pvc-name>

# Check controller logs
kubectl logs -n kube-system -l app=ebs-csi-controller

# Check IAM role
kubectl get sa ebs-csi-controller-sa -n kube-system -o yaml | grep eks.amazonaws.com/role-arn
```

### Volume Attachment Failures

**Symptoms**: Pod can't start, volume attachment errors

**Debug**:
```bash
# Check node driver logs
kubectl logs -n kube-system -l app=ebs-csi-node --tail=50

# Check EC2 volume attachments
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=<pvc-name>"
```

### Performance Issues

**Investigation**:
```bash
# Check volume IOPS and throughput
kubectl describe pv <pv-name>

# Monitor volume metrics
kubectl top pv

# Check EBS volume metrics in CloudWatch
```

**Solutions**:
- Upgrade to `io2` StorageClass for higher IOPS
- Increase volume size (gp3 IOPS scales with size)
- Check application I/O patterns

## Cost Optimization

### Dev Environment Best Practices

1. **Use gp3 by default** - 20% cheaper than gp2
2. **Delete unused volumes** - Set reclaim policy to `Delete`
3. **Right-size volumes** - Start small, expand as needed
4. **Avoid io2** - Use only for performance testing
5. **Cleanup snapshots** - Delete old snapshots regularly

### Cost Monitoring

```bash
# List all EBS volumes managed by CSI
kubectl get pv -o json | jq -r '.items[] | select(.spec.csi.driver=="ebs.csi.aws.com") | .spec.csi.volumeHandle'

# Tag volumes for cost allocation
# (automatically tagged via extraVolumeTags in values.yaml)
```

## Migration from Legacy gp2

If you have existing PVCs using the old `gp2` StorageClass:

1. **Snapshot existing volume**
2. **Create new PVC with gp3**
3. **Restore from snapshot**
4. **Update application**
5. **Delete old PVC**

**Automated migration** (per PVC):
```bash
# Create snapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: <pvc-name>-migration
spec:
  source:
    persistentVolumeClaimName: <pvc-name>
EOF

# Create new gp3 PVC from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <pvc-name>-gp3
spec:
  dataSource:
    name: <pvc-name>-migration
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  storageClassName: gp3
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <size>Gi
EOF

# Update StatefulSet/Deployment to use new PVC
# Delete old PVC after verification
```

## References

- [AWS EBS CSI Driver Documentation](https://github.com/kubernetes-sigs/aws-ebs-csi-driver)
- [EKS Storage Best Practices](https://docs.aws.amazon.com/eks/latest/userguide/storage.html)
- [EBS Volume Types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html)
- [Storage Classes in Kubernetes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
