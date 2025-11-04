# Cross-Zone Load Balancing Decision

**Date**: 2025-11-03
**Decision**: ✅ **ENABLE cross-zone load balancing**
**Status**: Recommended (not yet implemented)

---

## Context

The EKS cluster has 3 Network Load Balancers (NLBs) for internal services:
- ArgoCD Server
- Grafana Dashboard
- Prometheus Server

**Current Configuration**:
- Cross-zone load balancing: **DISABLED**
- Load balancers span: us-east-2a, us-east-2b, us-east-2c
- Node distribution: 1 node per AZ (balanced)
- Pod distribution: Unbalanced (27, 5, 21 pods)

---

## Problem Statement

Without cross-zone load balancing:
- Traffic arriving in us-east-2b only routes to the 5 pods in that AZ
- Traffic arriving in us-east-2a only routes to the 27 pods in that AZ
- Result: **Uneven load distribution** and potential performance bottlenecks

---

## Decision: Enable Cross-Zone Load Balancing

### Rationale

1. **Better Traffic Distribution**: Evenly distributes traffic across all healthy targets regardless of AZ
2. **Improved Resilience**: Better handling of AZ-specific issues or pod failures
3. **Resource Utilization**: Prevents hotspots where some pods are overloaded while others are idle
4. **Consistent Performance**: Users get consistent response times regardless of which AZ they route through

### Trade-offs Accepted

**Cost**: ~$5-20/month in cross-AZ data transfer fees
- Internal services have moderate traffic
- Cost is minimal compared to operational benefits

**Latency**: +1-2ms cross-AZ latency
- Negligible for dashboard/UI applications
- Not latency-sensitive workloads

---

## Implementation Options

### Option 1: Enable at Service Level (Recommended)

Add annotation to Kubernetes services:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argo-cd-argocd-server
  namespace: argocd
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
```

**Pros**:
- Granular control per service
- Infrastructure-as-code (GitOps friendly)
- Easy to audit and version control

**Cons**:
- Requires updating each service manifest
- Needs redeployment of services

### Option 2: Enable via AWS Console/CLI

Directly modify NLB attributes:

```bash
export AWS_PROFILE=ims-platform-dev

# Enable for ArgoCD LB
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <argocd-lb-arn> \
  --attributes Key=load_balancing.cross_zone.enabled,Value=true

# Enable for Grafana LB
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <grafana-lb-arn> \
  --attributes Key=load_balancing.cross_zone.enabled,Value=true

# Enable for Prometheus LB
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <prometheus-lb-arn> \
  --attributes Key=load_balancing.cross_zone.enabled,Value=true
```

**Pros**:
- Immediate effect (no redeployment needed)
- Quick implementation

**Cons**:
- Configuration drift (not in Git)
- Can be overwritten by future service updates
- Not GitOps compliant

### Option 3: Enable by Default for All Services

Configure AWS Load Balancer Controller to enable by default:

```yaml
# In AWS Load Balancer Controller configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
data:
  enable-cross-zone-load-balancing: "true"
```

**Pros**:
- All future NLBs get cross-zone by default
- Consistent configuration

**Cons**:
- Affects all services (may want selective control)
- Requires Load Balancer Controller update

---

## Recommended Implementation Plan

### Phase 1: Enable via Service Annotations (GitOps)

**Step 1: Update Service Manifests**

For each LoadBalancer service, add annotation:

```yaml
service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
```

**Services to update**:
1. `argocd/argo-cd-argocd-server`
2. `kube-prometheus-stack/kube-prometheus-stack-grafana`
3. `kube-prometheus-stack/kube-prometheus-stack-prometheus`

**Step 2: Apply Changes**

```bash
# If managed by ArgoCD (recommended)
# ArgoCD will detect changes and sync automatically

# Or apply manually
kubectl apply -f <updated-service-manifest.yaml>
```

**Step 3: Verify**

```bash
export AWS_PROFILE=ims-platform-dev

# Check each LB
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <lb-arn> \
  --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`]'
```

### Phase 2: Monitor Impact

**Metrics to watch**:
1. **Cost**: Monitor cross-AZ data transfer in AWS Cost Explorer
2. **Performance**: Check service response times in Grafana
3. **Traffic distribution**: Monitor target health and request counts per AZ

**Monitoring Period**: 7 days

---

## Service-Specific Recommendations

### ArgoCD Server
- **Traffic Pattern**: Bursty (user dashboard access, webhook callbacks)
- **Priority**: High (critical CI/CD infrastructure)
- **Recommendation**: ✅ **Enable** - Ensures consistent access regardless of AZ

### Grafana Dashboard
- **Traffic Pattern**: Moderate (dashboard queries, alerts)
- **Priority**: Medium (monitoring visibility)
- **Recommendation**: ✅ **Enable** - Better user experience across teams

### Prometheus Server
- **Traffic Pattern**: High (constant metrics scraping from all pods)
- **Priority**: High (observability foundation)
- **Recommendation**: ✅ **Enable** - Critical for balanced metrics collection

---

## Example Manifests

### ArgoCD Service with Cross-Zone

```yaml
apiVersion: v1
kind: Service
metadata:
  name: argo-cd-argocd-server
  namespace: argocd
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  ports:
  - name: http
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8080
  selector:
    app.kubernetes.io/name: argocd-server
```

### Grafana Service with Cross-Zone

```yaml
apiVersion: v1
kind: Service
metadata:
  name: kube-prometheus-stack-grafana
  namespace: kube-prometheus-stack
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
  selector:
    app.kubernetes.io/name: grafana
```

---

## Cost Analysis

### Data Transfer Pricing
- **Within AZ**: Free
- **Cross-AZ (us-east-2 region)**: $0.01/GB

### Estimated Monthly Costs

**Conservative Estimate** (based on internal services):
- ArgoCD: ~50 GB/month = $0.50
- Grafana: ~100 GB/month = $1.00
- Prometheus: ~500 GB/month = $5.00
- **Total**: ~$6.50/month

**High Usage Estimate**:
- ArgoCD: ~100 GB/month = $1.00
- Grafana: ~300 GB/month = $3.00
- Prometheus: ~1500 GB/month = $15.00
- **Total**: ~$19.00/month

**ROI**: Improved reliability and performance far outweigh minimal cost increase

---

## Rollback Plan

If issues arise, disable cross-zone load balancing:

### Quick Rollback (AWS CLI)
```bash
export AWS_PROFILE=ims-platform-dev

aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <lb-arn> \
  --attributes Key=load_balancing.cross_zone.enabled,Value=false
```

### GitOps Rollback
```bash
# Remove annotation from service manifests
# or change to "false"
service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "false"

# Commit and let ArgoCD sync
```

**Rollback Time**: ~2 minutes

---

## Validation Checklist

After enabling cross-zone load balancing:

- [ ] Verify NLB attributes show `cross_zone.enabled = true`
- [ ] Check target health across all AZs (should be healthy)
- [ ] Monitor service response times (should be consistent)
- [ ] Verify traffic distribution is more balanced
- [ ] Check AWS Cost Explorer after 24-48 hours for cross-AZ data transfer
- [ ] Test service availability from all AZs
- [ ] Confirm ArgoCD syncs and deployments work normally
- [ ] Verify Grafana dashboards load consistently
- [ ] Check Prometheus metrics collection is stable

---

## Related Documentation

- AWS NLB Cross-Zone: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/network-load-balancers.html#cross-zone-load-balancing
- AWS Load Balancer Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- IP Rebalancing Results: `docs/IP-REBALANCING-RESULTS.md`
- Architecture: `docs/ARCHITECTURE.md`

---

## Decision Log

| Date | Decision | Rationale | Implemented |
|------|----------|-----------|-------------|
| 2025-11-03 | Enable cross-zone LB | Better traffic distribution, minimal cost | ⏳ Pending |

---

## Commands Reference

### Check Current Configuration
```bash
export AWS_PROFILE=ims-platform-dev

# List all NLBs
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-`)].{Name:LoadBalancerName,ARN:LoadBalancerArn}' \
  --output table

# Check cross-zone setting
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <arn> \
  --query 'Attributes[?Key==`load_balancing.cross_zone.enabled`]'
```

### Enable Cross-Zone
```bash
# Via AWS CLI
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <arn> \
  --attributes Key=load_balancing.cross_zone.enabled,Value=true

# Via Kubernetes annotation (add to service)
kubectl annotate svc <service-name> -n <namespace> \
  service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled=true
```

### Monitor Impact
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn>

# Monitor CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkELB \
  --metric-name ProcessedBytes \
  --dimensions Name=LoadBalancer,Value=<lb-name> \
  --start-time <timestamp> \
  --end-time <timestamp> \
  --period 3600 \
  --statistics Sum
```

---

## Approval

**Recommended by**: Claude Code AI Assistant
**Date**: 2025-11-03
**Decision Owner**: austincarter
**Implementation Status**: ⏳ Awaiting approval and implementation

---

## Next Steps

1. ✅ Review this decision document
2. ⏳ Approve implementation approach (Option 1 recommended)
3. ⏳ Update service manifests with cross-zone annotation
4. ⏳ Deploy via ArgoCD or apply manually
5. ⏳ Monitor for 7 days
6. ⏳ Document results and finalize decision
