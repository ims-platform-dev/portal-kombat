# Port.io + Crossplane Integration Setup Guide

## Prerequisites

### Required Access
- [x] Port.io Team tier account
- [x] Portal Kombat Kubernetes cluster access (kubectl)
- [x] AWS account access (for IRSA configuration)
- [x] GitHub repository admin access (for GitHub App creation)
- [x] ArgoCD access (for deployment management)

### Required Tools
```bash
# Verify tool versions
kubectl version --client  # 1.28+
helm version              # 3.12+
argocd version --client   # 2.10+
aws --version             # 2.0+
```

### Port.io Team Tier
This integration requires Port.io Team tier for:
- RBAC and team-based access control
- Audit logs for compliance
- SSO integration (optional)
- Webhook support
- API rate limits sufficient for production

**Cost**: Approximately $495/month for 10-20 developers

## Phase 1: Port.io Platform Setup

### Step 1: Create Port.io Organization

1. Sign up for Port.io Team tier at https://app.getport.io/
2. Create organization: `portal-kombat`
3. Invite team members with appropriate roles:
   - **Admin**: Platform engineering team
   - **Member**: Application developers

### Step 2: Generate Port.io API Credentials

1. Navigate to Port.io Settings → Credentials
2. Create new API credentials:
   - **Name**: `crossplane-sync`
   - **Description**: `Kubernetes exporter for Crossplane resource synchronization`
   - **Permissions**: Read-write access to blueprints and entities
3. Save credentials securely (you'll need them for Kubernetes secret creation)

```bash
# Save credentials for later use
export PORT_CLIENT_ID="your-client-id"
export PORT_CLIENT_SECRET="your-client-secret"
```

### Step 3: Create Port.io Blueprints

#### S3 Bucket Blueprint

1. Navigate to Port.io → Builder → Blueprints
2. Click "Create Blueprint"
3. Use the configuration from `config/port-io/blueprints/s3-bucket.json`

**Or use Port.io API**:
```bash
curl -X POST "https://api.getport.io/v1/blueprints" \
  -H "Authorization: Bearer ${PORT_CLIENT_ID}:${PORT_CLIENT_SECRET}" \
  -H "Content-Type: application/json" \
  -d @config/port-io/blueprints/s3-bucket.json
```

#### ObjectStorage Claim Blueprint

1. Create second blueprint for Crossplane claims
2. Use configuration from `config/port-io/blueprints/object-storage-claim.json`

```bash
curl -X POST "https://api.getport.io/v1/blueprints" \
  -H "Authorization: Bearer ${PORT_CLIENT_ID}:${PORT_CLIENT_SECRET}" \
  -H "Content-Type: application/json" \
  -d @config/port-io/blueprints/object-storage-claim.json
```

### Step 4: Configure Webhook Endpoint

1. Navigate to Port.io → Settings → Webhooks
2. Create webhook for self-service actions:
   - **URL**: `https://port-webhook.portal-kombat.dev/webhooks/port`
   - **Secret**: Generate strong secret (save for Kubernetes secret)
   - **Events**: Action executions
3. Save webhook secret:

```bash
export PORT_WEBHOOK_SECRET="your-webhook-secret"
```

## Phase 2: Kubernetes Cluster Setup

### Step 1: Create Kubernetes Secrets

```bash
# Connect to dev cluster
kubectl config use-context portal-kombat-dev-raiden

# Create namespace
kubectl create namespace port-sync

# Create Port.io API credentials secret
kubectl create secret generic port-api-credentials \
  --namespace=port-sync \
  --from-literal=PORT_CLIENT_ID="${PORT_CLIENT_ID}" \
  --from-literal=PORT_CLIENT_SECRET="${PORT_CLIENT_SECRET}"

# Create webhook secret
kubectl create secret generic port-webhook-secret \
  --namespace=port-sync \
  --from-literal=WEBHOOK_SECRET="${PORT_WEBHOOK_SECRET}"

# Verify secrets created
kubectl get secrets -n port-sync
```

### Step 2: Deploy Port.io Kubernetes Exporter

The Port.io Kubernetes exporter watches Crossplane resources and syncs them to Port.io.

```bash
# Navigate to exporter configuration
cd environments/dev/cluster-addons/port-exporter

# Review configuration
cat values.yaml

# Apply ArgoCD application
kubectl apply -f application.yaml

# Watch deployment
kubectl get applications -n argocd -w
# Wait for port-exporter to show "Synced" and "Healthy"
```

**Verify exporter is running**:
```bash
# Check exporter pods
kubectl get pods -n port-sync -l app=port-exporter

# Check exporter logs
kubectl logs -n port-sync -l app=port-exporter --tail=50

# Expected output:
# INFO  Starting Port.io Kubernetes exporter
# INFO  Connected to Port.io API
# INFO  Watching Crossplane resources...
```

### Step 3: Verify Resource Synchronization

```bash
# Check existing Crossplane resources
kubectl get objectstorage -A
kubectl get bucket -A

# Wait 5 minutes for initial sync
sleep 300

# Verify in Port.io UI:
# 1. Navigate to Port.io → Catalog
# 2. Filter by blueprint: "s3-bucket"
# 3. You should see all Crossplane S3 buckets listed
```

**Troubleshooting sync issues**:
```bash
# Check exporter events
kubectl get events -n port-sync --sort-by='.lastTimestamp'

# Check exporter metrics
kubectl port-forward -n port-sync svc/port-exporter 8080:8080
curl http://localhost:8080/metrics | grep port_sync

# Common issues:
# - API credentials incorrect: Check secret values
# - Network connectivity: Check egress to api.getport.io
# - Blueprint mismatch: Verify blueprint IDs match configuration
```

## Phase 3: Self-Service Setup (GitHub Actions)

### Step 1: Create GitHub App

1. Navigate to GitHub → Settings → Developer settings → GitHub Apps
2. Click "New GitHub App"
3. Configuration:
   - **Name**: `portal-kombat-port-io`
   - **Homepage URL**: `https://port-webhook.portal-kombat.dev`
   - **Webhook URL**: `https://port-webhook.portal-kombat.dev/github`
   - **Webhook secret**: Generate and save
   - **Repository permissions**:
     - Contents: Read & Write
     - Pull requests: Read & Write
     - Workflows: Read & Write
   - **Subscribe to events**: Pull request, Workflow dispatch
4. Generate private key and download
5. Install app on `portal-kombat` repository

```bash
# Save GitHub App credentials
export GITHUB_APP_ID="your-app-id"
export GITHUB_APP_PRIVATE_KEY_PATH="path-to-private-key.pem"
```

### Step 2: Deploy Self-Hosted GitHub Actions Runners

```bash
# Create namespace
kubectl create namespace github-runners

# Create GitHub App secret
kubectl create secret generic github-app-credentials \
  --namespace=github-runners \
  --from-literal=GITHUB_APP_ID="${GITHUB_APP_ID}" \
  --from-file=GITHUB_APP_PRIVATE_KEY="${GITHUB_APP_PRIVATE_KEY_PATH}"

# Deploy actions-runner-controller via ArgoCD
kubectl apply -f environments/dev/cluster-addons/github-runners/application.yaml

# Verify runners deployed
kubectl get pods -n github-runners
kubectl logs -n github-runners -l app=actions-runner-controller

# Check runner registration in GitHub
# Navigate to: https://github.com/your-org/portal-kombat/settings/actions/runners
# You should see 2-3 runners with status "Idle"
```

### Step 3: Deploy Webhook Receiver Service

```bash
# Build webhook receiver Docker image (if not already built)
cd services/webhook-receiver
docker build -t webhook-receiver:v1.0.0 .

# Tag and push to ECR
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com
docker tag webhook-receiver:v1.0.0 ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/webhook-receiver:v1.0.0
docker push ACCOUNT_ID.dkr.ecr.us-east-2.amazonaws.com/webhook-receiver:v1.0.0

# Deploy via ArgoCD
kubectl apply -f environments/dev/cluster-addons/webhook-receiver/deployment.yaml
kubectl apply -f environments/dev/cluster-addons/webhook-receiver/service.yaml
kubectl apply -f environments/dev/cluster-addons/webhook-receiver/ingress.yaml

# Verify webhook receiver running
kubectl get pods -n port-sync -l app=webhook-receiver
kubectl logs -n port-sync -l app=webhook-receiver --tail=50

# Verify ingress created
kubectl get ingress -n port-sync
```

### Step 4: Configure DNS and TLS

```bash
# Verify external-dns created DNS record
kubectl get ingress -n port-sync webhook-receiver -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Verify cert-manager issued certificate
kubectl get certificate -n port-sync webhook-receiver-tls
# Wait for status: Ready

# Test webhook endpoint
curl -k https://port-webhook.portal-kombat.dev/health
# Expected: {"status":"healthy"}
```

## Phase 4: Port.io Self-Service Actions

### Step 1: Create Self-Service Action

1. Navigate to Port.io → Self-Service
2. Click "Create Action"
3. Use configuration from `config/port-io/actions/provision-s3-bucket.json`

**Configuration**:
- **Name**: `Provision S3 Bucket`
- **Blueprint**: `object-storage-claim`
- **Trigger**: Manual
- **Inputs**:
  - Bucket purpose (text)
  - Environment (select: dev, staging, prod)
  - Team name (text)
  - Enable versioning (boolean)
- **Backend**: Webhook
- **Webhook URL**: `https://port-webhook.portal-kombat.dev/webhooks/port`

### Step 2: Test Self-Service Flow

1. Navigate to Port.io → Self-Service → Provision S3 Bucket
2. Fill in form:
   - **Bucket purpose**: `test-integration`
   - **Environment**: `dev`
   - **Team**: `platform`
   - **Versioning**: `true`
3. Click "Execute"
4. Monitor progress:
   - Port.io shows run status (In Progress → Success)
   - GitHub shows new PR created
   - ArgoCD syncs after PR merge
   - Crossplane provisions S3 bucket
   - Port.io catalog updated with new bucket

**Verify end-to-end flow**:
```bash
# Check GitHub PRs
gh pr list --repo your-org/portal-kombat

# Check ArgoCD sync status
kubectl get applications -n argocd

# Check Crossplane resource created
kubectl get objectstorage -n dev | grep test-integration

# Check Port.io catalog updated
# Navigate to Port.io → Catalog → Search "test-integration"
```

## Phase 5: Monitoring Setup

### Step 1: Deploy Prometheus Rules

```bash
# Apply Prometheus alert rules
kubectl apply -f monitoring/prometheus-rules/port-io-alerts.yaml

# Verify rules loaded
kubectl get prometheusrules -n monitoring port-io-sync
```

### Step 2: Deploy Grafana Dashboard

```bash
# Create Grafana dashboard configmap
kubectl create configmap port-io-sync-dashboard \
  --namespace=monitoring \
  --from-file=monitoring/grafana-dashboards/port-io-sync.json

# Label for Grafana discovery
kubectl label configmap port-io-sync-dashboard \
  --namespace=monitoring \
  grafana_dashboard=1

# Verify dashboard appears in Grafana
# Navigate to Grafana → Dashboards → Search "Port.io"
```

### Step 3: Configure Alertmanager

```bash
# Update Alertmanager configuration with Port.io routes
# Edit: monitoring/alertmanager-config.yaml
kubectl apply -f monitoring/alertmanager-config.yaml

# Verify alert routing
kubectl get secret -n monitoring alertmanager-main -o yaml
```

## Phase 6: Validation and Testing

### Checklist

**Port.io Platform**:
- [ ] Port.io blueprints created (s3-bucket, object-storage-claim)
- [ ] API credentials generated and stored in Kubernetes secret
- [ ] Webhook configured with correct URL and secret
- [ ] Self-service action created and functional

**Kubernetes Cluster**:
- [ ] Port.io exporter deployed and healthy
- [ ] Webhook receiver deployed and accessible
- [ ] GitHub Actions runners registered and idle
- [ ] TLS certificates issued by cert-manager
- [ ] DNS records created by external-dns

**Integration Verification**:
- [ ] Existing Crossplane resources synced to Port.io
- [ ] Port.io catalog displays all S3 buckets
- [ ] Health status accurate (Ready = Healthy)
- [ ] Self-service action creates PRs successfully
- [ ] GitHub Actions workflows execute correctly
- [ ] ArgoCD syncs infrastructure changes
- [ ] Crossplane provisions requested resources
- [ ] New resources appear in Port.io catalog

**Monitoring**:
- [ ] Prometheus rules deployed and firing (if issues exist)
- [ ] Grafana dashboard shows metrics
- [ ] Alertmanager routing configured
- [ ] Health checks passing

### Test Scenarios

#### Test 1: View Existing Infrastructure
```bash
# List existing buckets in Port.io
# Expected: All Crossplane S3 buckets visible
```

#### Test 2: Request New S3 Bucket (Dev - Auto-merge)
```bash
# Execute Port.io action: Provision S3 Bucket
# Bucket purpose: e2e-test-bucket
# Environment: dev
# Expected: PR auto-merged, bucket provisioned, catalog updated
```

#### Test 3: Request New S3 Bucket (Staging - Manual Approval)
```bash
# Execute Port.io action: Provision S3 Bucket
# Bucket purpose: e2e-test-bucket-staging
# Environment: staging
# Expected: PR created, requires manual approval, catalog updated after merge
```

#### Test 4: Monitor Sync Health
```bash
# View Grafana dashboard
# Expected: No errors, sync latency < 5 seconds
```

## Rollback Procedures

### Disable Self-Service (Emergency)
```bash
# Disable Port.io webhooks
# Navigate to Port.io → Settings → Webhooks → Disable

# Scale down webhook receiver
kubectl scale deployment webhook-receiver --replicas=0 -n port-sync

# Read-only sync continues, no new infrastructure requests accepted
```

### Rollback Port.io Exporter
```bash
# Scale down exporter
kubectl scale deployment port-exporter --replicas=0 -n port-sync

# Crossplane continues operating, no Port.io catalog updates
```

### Complete Rollback
```bash
# Delete ArgoCD applications
kubectl delete application port-exporter -n argocd
kubectl delete application github-runners -n argocd
kubectl delete application webhook-receiver -n argocd

# Delete namespaces
kubectl delete namespace port-sync
kubectl delete namespace github-runners

# No infrastructure impact - Crossplane continues managing AWS resources
```

## Post-Setup Tasks

### 1. Team Onboarding
- [ ] Share Port.io access with developers
- [ ] Conduct training session on self-service actions
- [ ] Distribute developer guide: `docs/port-io-integration/02-developer-guide.md`

### 2. Documentation
- [ ] Update runbook with environment-specific details
- [ ] Document custom blueprints and actions
- [ ] Create FAQ for common issues

### 3. Operational Excellence
- [ ] Set up on-call rotation for Port.io integration
- [ ] Schedule monthly review of sync health metrics
- [ ] Plan quarterly blueprint and action reviews

## Troubleshooting

See [Troubleshooting Guide](03-troubleshooting.md) for detailed issue resolution.

**Quick Diagnostics**:
```bash
# Check exporter health
kubectl get pods -n port-sync -l app=port-exporter
kubectl logs -n port-sync -l app=port-exporter --tail=100

# Check webhook receiver health
curl https://port-webhook.portal-kombat.dev/health

# Check GitHub runners
kubectl get pods -n github-runners
gh api /repos/your-org/portal-kombat/actions/runners

# Check Crossplane resources
kubectl get managed -A
kubectl get objectstorage -A
```

## Support and Resources

**Documentation**:
- [Overview](00-overview.md)
- [Developer Guide](02-developer-guide.md)
- [Troubleshooting](03-troubleshooting.md)
- [Architecture](04-architecture.md)

**External Resources**:
- [Port.io Documentation](https://docs.getport.io/)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [actions-runner-controller](https://github.com/actions/actions-runner-controller)

**Support Channels**:
- Platform Engineering Team: `#platform-engineering` (Slack)
- Port.io Support: support@getport.io
- On-Call: PagerDuty escalation policy

---
**Last Updated**: 2025-11-06
**Version**: 1.0
**Maintainer**: Platform Engineering Team
