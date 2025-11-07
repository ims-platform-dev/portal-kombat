# Port.io + Crossplane Troubleshooting Guide

## Quick Diagnostics

```bash
# Check Port.io exporter health
kubectl get pods -n port-sync -l app=port-exporter
kubectl logs -n port-sync -l app=port-exporter --tail=100

# Check webhook receiver health
curl https://port-webhook.portal-kombat.dev/health
kubectl logs -n port-sync -l app=webhook-receiver --tail=100

# Check GitHub Actions runners
kubectl get pods -n github-runners
gh api /repos/your-org/portal-kombat/actions/runners

# Check Crossplane resources
kubectl get managed -A
kubectl get objectstorage -A
```

## Common Issues

### Issue 1: Port.io Exporter Not Syncing

**Symptoms**:
- Resources not appearing in Port.io catalog
- Exporter pod crashlooping
- Sync metrics showing failures

**Diagnosis**:
```bash
# Check exporter logs
kubectl logs -n port-sync -l app=port-exporter --tail=200

# Check Port.io API credentials
kubectl get secret port-api-credentials -n port-sync -o yaml

# Test Port.io API connectivity
kubectl exec -n port-sync deployment/port-exporter -- curl -v https://api.getport.io/v1/blueprints
```

**Solutions**:
1. **Invalid API credentials**: Rotate Port.io API token
2. **Network connectivity**: Check egress rules to api.getport.io
3. **Rate limiting**: Check Prometheus metrics for rate limit errors
4. **Blueprint mismatch**: Verify blueprint IDs match exporter config

### Issue 2: Webhook Signature Verification Failures

**Symptoms**:
- Port.io actions fail immediately
- Webhook receiver logs show "Invalid signature"
- HTTP 401 responses

**Diagnosis**:
```bash
# Check webhook secret matches
kubectl get secret port-webhook-secret -n port-sync -o jsonpath='{.data.WEBHOOK_SECRET}' | base64 -d

# Check webhook receiver logs
kubectl logs -n port-sync -l app=webhook-receiver --tail=50 | grep signature
```

**Solutions**:
1. **Secret mismatch**: Ensure Port.io webhook secret matches Kubernetes secret
2. **Secret rotation**: Update both Port.io and Kubernetes with new secret
3. **Encoding issues**: Verify no extra whitespace in secret values

### Issue 3: GitHub Actions Workflow Not Triggering

**Symptoms**:
- Port.io run stuck "In Progress"
- No PR created in GitHub
- GitHub API errors in webhook receiver logs

**Diagnosis**:
```bash
# Check webhook receiver logs
kubectl logs -n port-sync -l app=webhook-receiver | grep github

# Check GitHub token validity
gh auth status

# Check repository dispatch permissions
gh api repos/your-org/portal-kombat/dispatches
```

**Solutions**:
1. **Invalid GitHub token**: Regenerate GitHub App private key
2. **Insufficient permissions**: Verify GitHub App has repository dispatch permission
3. **Runner queue full**: Scale up GitHub Actions runners

### Issue 4: Crossplane Resource Provisioning Failed

**Symptoms**:
- ObjectStorage claim status: Failed
- S3 bucket not created in AWS
- Crossplane provider errors

**Diagnosis**:
```bash
# Check ObjectStorage claim status
kubectl describe objectstorage CLAIM_NAME -n ENVIRONMENT

# Check Crossplane provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=100

# Check IAM permissions
kubectl describe sa -n crossplane-system | grep eks.amazonaws.com/role-arn
```

**Solutions**:
1. **IAM permissions**: Verify IRSA role has S3 permissions
2. **Invalid parameters**: Check bucket name uniqueness globally
3. **Provider not healthy**: Restart provider pod
4. **AWS API errors**: Check CloudTrail for access denied errors

### Issue 5: Data Not Syncing to Port.io

**Symptoms**:
- Crossplane resource exists but not in Port.io
- Outdated status in Port.io catalog
- Exporter running but sync metrics low

**Diagnosis**:
```bash
# Check exporter is watching correct resources
kubectl get objectstorage -A --show-labels

# Check exporter configuration
kubectl get application port-exporter -n argocd -o yaml

# Check Port.io API responses
kubectl logs -n port-sync -l app=port-exporter | grep "Port.io API"
```

**Solutions**:
1. **Label mismatch**: Add required labels to Crossplane resources
2. **Namespace filtering**: Check exporter selector query
3. **Blueprint mismatch**: Verify blueprint identifier matches
4. **Manual refresh**: Delete and recreate Port.io entity

## Monitoring and Alerts

### Metrics to Monitor

**Port.io Exporter**:
```promql
# Sync success rate
rate(port_sync_entities_synced_total{status="success"}[5m]) /
rate(port_sync_entities_synced_total[5m])

# Sync latency (P95)
histogram_quantile(0.95, rate(port_sync_sync_duration_seconds_bucket[5m]))

# API errors
rate(port_sync_api_requests_total{status=~"5.."}[5m])
```

**Webhook Receiver**:
```promql
# Webhook processing success rate
rate(webhook_receiver_requests_total{status="success"}[5m]) /
rate(webhook_receiver_requests_total[5m])

# GitHub workflow trigger failures
rate(webhook_receiver_github_workflows_total{status="error"}[5m])
```

### Grafana Dashboards

Navigate to: Grafana → Dashboards → "Port.io Sync Health"

**Key Panels**:
- Service uptime and availability
- Sync operations per minute
- API call success/failure rates
- Webhook processing latency
- GitHub Actions runner status

### Alert Response

**Critical: Port.io Exporter Down**:
1. Check pod status: `kubectl get pods -n port-sync`
2. Check logs for crash reason
3. Restart if configuration issue: `kubectl rollout restart deployment/port-exporter -n port-sync`
4. Escalate to on-call if persistent

**Warning: High Sync Latency**:
1. Check Port.io API rate limits
2. Check Crossplane resource count
3. Scale exporter horizontally if needed
4. Investigate slow API responses

## Emergency Procedures

### Disable Self-Service (Emergency)

```bash
# Stop accepting new infrastructure requests
kubectl scale deployment webhook-receiver --replicas=0 -n port-sync

# Read-only sync continues, no new provisioning
```

### Rollback Integration

```bash
# Delete all Port.io integration components
kubectl delete application port-exporter -n argocd
kubectl delete application github-runners -n argocd
kubectl delete application webhook-receiver -n argocd

# Crossplane continues managing infrastructure
# No impact to running applications
```

### Manual Sync

```bash
# Force sync specific resource to Port.io
kubectl annotate objectstorage RESOURCE_NAME -n NAMESPACE \
  port.io/force-sync="$(date +%s)"

# Exporter will detect annotation and trigger sync
```

## Contact and Escalation

**Platform Engineering Team**:
- Slack: `#platform-engineering`
- PagerDuty: Platform on-call

**Port.io Support**:
- Email: support@getport.io
- Documentation: https://docs.getport.io/

**Crossplane Support**:
- Slack: CNCF #crossplane
- GitHub: https://github.com/crossplane/crossplane

---
**Last Updated**: 2025-11-06
**Version**: 1.0
