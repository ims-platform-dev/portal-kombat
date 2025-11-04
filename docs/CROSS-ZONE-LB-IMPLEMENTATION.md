# Cross-Zone Load Balancing Implementation

**Date**: 2025-11-03
**Status**: ✅ Configuration Updated - Ready for Deployment
**Implementation Method**: GitOps via Helm values

---

## Changes Made

Updated 3 Helm values files to enable cross-zone load balancing:

### 1. ArgoCD Server (`bootstrap/eks-bootstrap/values/argocd.yaml`)
```yaml
server:
  service:
    type: "LoadBalancer"
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"  # ← ADDED
```

### 2. Prometheus (`bootstrap/eks-bootstrap/values/prometheus.yaml`)
```yaml
prometheus:
  service:
    type: "LoadBalancer"
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"  # ← ADDED
```

### 3. Grafana (`bootstrap/eks-bootstrap/values/prometheus.yaml`)
```yaml
grafana:
  service:
    type: "LoadBalancer"
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
      service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"  # ← ADDED
```

---

## Deployment Options

### Option A: Terraform Apply (Recommended - One Command)

Since these are managed by Terraform in `bootstrap/eks-bootstrap/`, apply via Terraform:

```bash
cd bootstrap/eks-bootstrap

# Review changes
terraform plan -var-file=shaiden.tfvars

# Apply changes
terraform apply -var-file=shaiden.tfvars
```

**What happens**:
- Terraform updates Helm releases
- Helm recreates LoadBalancer services with new annotations
- AWS Load Balancer Controller detects changes and updates NLB attributes
- Services remain available (brief interruption during LB update)

**Estimated downtime**: 30-60 seconds per service (rolling update)

---

### Option B: Manual Helm Upgrade (If not using Terraform)

If you deployed ArgoCD and Prometheus manually with Helm:

```bash
# Upgrade ArgoCD
helm upgrade argo-cd argo/argo-cd \
  -n argocd \
  -f bootstrap/eks-bootstrap/values/argocd.yaml

# Upgrade Prometheus/Grafana stack
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n kube-prometheus-stack \
  -f bootstrap/eks-bootstrap/values/prometheus.yaml
```

---

### Option C: Force Service Recreation (Fastest)

Force Kubernetes to recreate the services:

```bash
# Delete and recreate services (AWS LB Controller will handle LB updates)
kubectl delete svc argo-cd-argocd-server -n argocd
kubectl delete svc kube-prometheus-stack-grafana -n kube-prometheus-stack
kubectl delete svc kube-prometheus-stack-prometheus -n kube-prometheus-stack

# Services will be recreated automatically by Helm/controllers
# Wait 1-2 minutes for recreation
```

**Warning**: This causes brief downtime (1-2 minutes) while LBs are recreated

---

## Recommended Deployment Plan

### Pre-Deployment Checklist

- [x] Changes made to values files
- [ ] Review git diff to confirm changes
- [ ] Backup current LoadBalancer URLs
- [ ] Notify team of planned maintenance window (optional)
- [ ] Confirm you have AWS credentials configured

### Deployment Steps

**Step 1: Review Changes**
```bash
cd /Users/austincarter/Development/personal/portal-kombat
git status
git diff bootstrap/eks-bootstrap/values/
```

**Step 2: Commit Changes**
```bash
git add bootstrap/eks-bootstrap/values/argocd.yaml
git add bootstrap/eks-bootstrap/values/prometheus.yaml
git commit -m "Enable cross-zone load balancing for ArgoCD, Prometheus, and Grafana

- Add cross-zone load balancing annotation to NLB services
- Improves traffic distribution across all healthy pods
- Prevents AZ-specific hotspots
- Estimated cost impact: $5-20/month

Related: docs/CROSS-ZONE-LB-DECISION.md"
```

**Step 3: Deploy via Terraform**
```bash
cd bootstrap/eks-bootstrap
export AWS_PROFILE=ims-platform-dev

# Dry run
terraform plan -var-file=shaiden.tfvars

# Apply (auto-approve only if you've reviewed the plan)
terraform apply -var-file=shaiden.tfvars
```

**Step 4: Monitor Deployment**
```bash
# Watch service updates
kubectl get svc -n argocd -w
kubectl get svc -n kube-prometheus-stack -w

# Check events
kubectl get events -n argocd --sort-by='.lastTimestamp' | tail -20
kubectl get events -n kube-prometheus-stack --sort-by='.lastTimestamp' | tail -20
```

**Step 5: Verify Cross-Zone Enabled**
```bash
export AWS_PROFILE=ims-platform-dev

# Get LoadBalancer ARNs
ARGOCD_LB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-argocd-argocdar`)].LoadBalancerArn' \
  --output text)

GRAFANA_LB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-kubeprom-kubeprom-9c`)].LoadBalancerArn' \
  --output text)

PROMETHEUS_LB_ARN=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-kubeprom-kubeprom-0f`)].LoadBalancerArn' \
  --output text)

# Verify cross-zone enabled
echo "=== ArgoCD ==="
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn $ARGOCD_LB_ARN \
  --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`]'

echo "=== Grafana ==="
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn $GRAFANA_LB_ARN \
  --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`]'

echo "=== Prometheus ==="
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn $PROMETHEUS_LB_ARN \
  --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`]'
```

**Expected Output**: All should show `"Value": "true"`

**Step 6: Test Services**
```bash
# Get LoadBalancer URLs
kubectl get svc argo-cd-argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get svc kube-prometheus-stack-grafana -n kube-prometheus-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get svc kube-prometheus-stack-prometheus -n kube-prometheus-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Access each service to verify functionality
# ArgoCD: http://<argocd-url>
# Grafana: http://<grafana-url>
# Prometheus: http://<prometheus-url>:9090
```

**Step 7: Monitor for 24 Hours**
- Check service response times in Grafana
- Monitor target health in AWS Console
- Watch for any connection issues
- Monitor AWS costs for cross-AZ data transfer

---

## Post-Deployment Validation

### Immediate Validation (5 minutes)

```bash
# 1. All services have LoadBalancer IPs
kubectl get svc -n argocd | grep LoadBalancer
kubectl get svc -n kube-prometheus-stack | grep LoadBalancer

# 2. All pods are Running
kubectl get pods -n argocd
kubectl get pods -n kube-prometheus-stack

# 3. Cross-zone enabled on all NLBs
export AWS_PROFILE=ims-platform-dev
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].LoadBalancerName' | \
  xargs -I {} aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?LoadBalancerName==`{}`].LoadBalancerArn' --output text) \
  --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`]'

# 4. Target health check
for lb in $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].LoadBalancerArn' --output text); do
  echo "=== $lb ==="
  aws elbv2 describe-target-health --target-group-arn $(aws elbv2 describe-target-groups --load-balancer-arn $lb --query 'TargetGroups[0].TargetGroupArn' --output text)
done
```

### 24-Hour Monitoring

**Metrics to Watch**:
1. **Service availability**: Check uptime/downtime
2. **Response times**: Monitor latency in Grafana dashboards
3. **Error rates**: Check for increased 5xx errors
4. **Cross-AZ data transfer**: Monitor in AWS Cost Explorer

**Expected Results**:
- ✅ No service downtime beyond initial deployment
- ✅ Consistent response times across all requests
- ✅ Even target distribution across all healthy pods
- ✅ Minor cost increase ($5-20/month)

---

## Rollback Procedure

If issues arise, rollback by removing the annotations:

### Quick Rollback (CLI)

```bash
export AWS_PROFILE=ims-platform-dev

# Disable cross-zone on all NLBs
for lb in $(aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].LoadBalancerArn' --output text); do
  aws elbv2 modify-load-balancer-attributes \
    --load-balancer-arn $lb \
    --attributes Key=load_balancing.cross_zone.enabled,Value=false
done
```

### GitOps Rollback

```bash
# Revert changes
git revert HEAD

# Re-apply via Terraform
cd bootstrap/eks-bootstrap
terraform apply -var-file=shaiden.tfvars
```

**Rollback Time**: 2-3 minutes

---

## Troubleshooting

### Issue: Services Not Recreating

**Symptom**: Services exist but cross-zone not applied

**Solution**:
```bash
# Force recreation
kubectl delete svc <service-name> -n <namespace>
# Wait 2 minutes for automatic recreation
kubectl get svc <service-name> -n <namespace>
```

### Issue: LoadBalancer Stuck in Pending

**Symptom**: Service shows `<pending>` for LoadBalancer IP

**Solution**:
```bash
# Check AWS Load Balancer Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# Check service events
kubectl describe svc <service-name> -n <namespace>
```

### Issue: Cross-Zone Not Enabled After Apply

**Symptom**: NLB attributes still show `"Value": "false"`

**Possible Causes**:
1. Helm chart needs service recreation (not just update)
2. AWS Load Balancer Controller version doesn't support annotation

**Solution**:
```bash
# Force service recreation
kubectl delete svc <service-name> -n <namespace>
# Let Helm recreate it automatically
```

---

## Cost Monitoring

### Set Up CloudWatch Alarms

```bash
export AWS_PROFILE=ims-platform-dev

# Alert if cross-AZ data transfer exceeds $50/month
aws cloudwatch put-metric-alarm \
  --alarm-name cross-az-data-transfer-high \
  --alarm-description "Cross-AZ data transfer cost exceeds threshold" \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --evaluation-periods 1 \
  --threshold 50 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=ServiceName,Value=DataTransfer-Regional
```

### Monitor Cost in AWS Console

1. Navigate to **AWS Cost Explorer**
2. Filter by: **Service** → **EC2-Other** (Data Transfer)
3. Group by: **Usage Type** → Look for `DataTransfer-Regional-Bytes`
4. Compare costs before/after implementation

**Expected Increase**: $5-20/month

---

## Success Criteria

- [x] Configuration updated in Git
- [ ] Changes deployed via Terraform
- [ ] All 3 NLBs show `cross_zone.enabled = true`
- [ ] All services accessible and functional
- [ ] Target health checks passing in all AZs
- [ ] No increase in error rates
- [ ] Response times remain consistent
- [ ] Cost increase within expected range ($5-20/month)

---

## Related Documentation

- Decision document: `docs/CROSS-ZONE-LB-DECISION.md`
- IP rebalancing: `docs/IP-REBALANCING-RESULTS.md`
- Architecture: `docs/ARCHITECTURE.md`
- Troubleshooting: `docs/TROUBLESHOOTING.md`

---

## Implementation Log

| Date | Action | Status | Notes |
|------|--------|--------|-------|
| 2025-11-03 | Values files updated | ✅ Complete | Added cross-zone annotations |
| 2025-11-03 | Ready for deployment | ⏳ Pending | Awaiting `terraform apply` |

---

## Quick Reference Commands

```bash
# Deploy changes
cd bootstrap/eks-bootstrap && terraform apply -var-file=shaiden.tfvars

# Verify cross-zone enabled
export AWS_PROFILE=ims-platform-dev
aws elbv2 describe-load-balancers --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].LoadBalancerName' | \
  xargs -I {} bash -c 'echo "=== {} ===" && aws elbv2 describe-load-balancer-attributes --load-balancer-arn $(aws elbv2 describe-load-balancers --query "LoadBalancers[?LoadBalancerName==\`{}\`].LoadBalancerArn" --output text) --query "Attributes[?Key==\`load_balancing.cross_zone.enabled\`]"'

# Check service health
kubectl get svc -A | grep LoadBalancer
kubectl get pods -n argocd
kubectl get pods -n kube-prometheus-stack

# Monitor costs
# Navigate to AWS Cost Explorer → Filter by EC2-Other (Data Transfer)
```
