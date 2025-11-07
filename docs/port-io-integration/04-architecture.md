# Port.io + Crossplane Integration Architecture

## System Overview

The Port.io + Crossplane integration provides bidirectional synchronization between Port.io (Developer Portal) and Crossplane (Infrastructure Platform), enabling centralized service catalog visibility and self-service infrastructure provisioning while maintaining GitOps principles.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Port.io Cloud                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Service    │  │   Blueprint  │  │   Webhook    │          │
│  │   Catalog    │  │   Builder    │  │   Manager    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │                 │
              Read Path          Write Path
              (Sync)            (Webhook)
                    │                 │
                    ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Portal Kombat EKS Cluster                     │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Port.io Kubernetes Exporter                    │ │
│  │  (Watches Crossplane → Syncs to Port.io)                   │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Webhook Receiver                         │ │
│  │  (Port.io Webhooks → GitHub Actions)                       │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Self-Hosted GitHub Actions Runners            │ │
│  │  (Generate YAML → Create PRs → Trigger GitOps)            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Crossplane Platform                      │ │
│  │  (Source of Truth for Infrastructure)                      │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │   GitHub Repo    │
                    │  portal-kombat   │
                    └──────────────────┘
                             │
                             ▼
                    ┌──────────────────┐
                    │   AWS Account    │
                    └──────────────────┘
```

## Component Details

### 1. Port.io Kubernetes Exporter (Read Path)

**Purpose**: Synchronize Crossplane resource state to Port.io catalog in real-time.

**Technology**:
- Helm chart: `port-k8s-exporter` v0.2.21
- Deployment: 2 replicas with HPA
- Namespace: `port-sync`

**Data Flow**:
1. Watches Kubernetes API for Crossplane CRDs
2. Transforms resources to Port.io entity format
3. Calls Port.io API to upsert entities
4. Updates every 30 seconds or on resource change

**Resources Watched**:
- `ObjectStorage` (Crossplane XR)
- `Bucket` (AWS S3 managed resource)
- Future: RDS, VPC, EKS

**Security**:
- RBAC: Read-only access to Crossplane CRDs
- Authentication: Port.io API token in Kubernetes secret
- Network: Egress to api.getport.io

### 2. Webhook Receiver Service (Write Path)

**Purpose**: Receive Port.io action webhooks and trigger infrastructure provisioning.

**Technology**:
- Language: Go 1.22
- Container: Distroless base image
- Deployment: 2 replicas
- Namespace: `port-sync`

**Data Flow**:
1. Receives HTTPS webhook from Port.io
2. Verifies HMAC-SHA256 signature
3. Validates payload schema
4. Triggers GitHub Actions workflow via repository dispatch
5. Returns acknowledgment to Port.io

**Security**:
- HMAC signature verification
- IP allowlist (Port.io webhook IPs)
- TLS termination at nginx-ingress
- Rate limiting: 100 req/min

### 3. Self-Hosted GitHub Actions Runners

**Purpose**: Execute infrastructure provisioning workflows in secure, controlled environment.

**Technology**:
- Controller: actions-runner-controller (ARC) v0.27.5
- Runners: Ephemeral (destroyed after each job)
- Scaling: HPA based on workflow queue depth
- Namespace: `github-runners`

**Workflow Steps**:
1. Validate infrastructure request
2. Generate Crossplane YAML from template
3. Create Git branch
4. Commit generated YAML
5. Push branch
6. Create Pull Request
7. Auto-merge (dev) or await approval (staging/prod)
8. Update Port.io run status

**Security**:
- Self-hosted (no cloud executor risk)
- Network policies isolate runner pods
- GitHub App authentication (scoped permissions)
- Ephemeral runners prevent state leakage

### 4. Crossplane Platform

**Purpose**: Provision and manage AWS infrastructure declaratively.

**Components**:
- XRDs: User-facing infrastructure APIs
- Compositions: Templates for AWS resource creation
- Providers: AWS S3, RDS, EC2, IAM
- Managed Resources: Actual AWS resources

**GitOps Flow**:
1. PR merged to main branch
2. ArgoCD detects Git change
3. ArgoCD syncs Crossplane resources
4. Crossplane reconciles AWS state
5. AWS resources provisioned

## Data Models

### Port.io Blueprint: S3 Bucket

```json
{
  "identifier": "s3-bucket",
  "properties": {
    "bucketName": "string",
    "region": "enum",
    "status": "enum",
    "environment": "string",
    "team": "string"
  },
  "relations": {
    "claim": "object-storage-claim",
    "cluster": "eks-cluster"
  }
}
```

### Crossplane ObjectStorage XR

```yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage
spec:
  parameters:
    bucketName: portal-kombat-dev-uploads-12345
    region: us-east-2
    versioning: true
status:
  conditions:
    - type: Ready
      status: "True"
  resourceRef:
    name: actual-s3-bucket-name
```

## Integration Patterns

### Pattern 1: Read-Only Sync (Crossplane → Port.io)

```
Crossplane creates resource
        ↓
Kubernetes API emits event
        ↓
Port.io exporter receives via Watch API
        ↓
Transform to Port.io entity format
        ↓
Call Port.io API (upsert)
        ↓
Port.io catalog updated
```

**Latency**: < 5 seconds

### Pattern 2: Self-Service Provisioning (Port.io → Crossplane)

```
Developer submits Port.io action
        ↓
Port.io sends webhook to receiver
        ↓
Webhook receiver validates and triggers GitHub Actions
        ↓
GitHub Actions generates Crossplane YAML
        ↓
Creates Pull Request
        ↓
(Dev: auto-merge | Staging/Prod: manual approval)
        ↓
ArgoCD syncs from Git
        ↓
Crossplane provisions AWS resource
        ↓
Port.io exporter syncs back to catalog
```

**Latency**: 10-30 minutes (depending on approval)

## Security Architecture

### Authentication Layer

- **Port.io API**: Client ID + Secret (OAuth2)
- **GitHub**: GitHub App with repository-scoped token
- **Kubernetes**: Service accounts with RBAC
- **AWS**: IRSA (IAM Roles for Service Accounts)

### Network Security

- **Ingress**: nginx-ingress with TLS (cert-manager)
- **Egress**: Restricted to api.getport.io, api.github.com
- **Network Policies**: Isolate port-sync namespace

### Data Security

- **Secrets**: Kubernetes Secrets with encryption at rest
- **TLS**: All external communication encrypted
- **Audit**: All actions logged with correlation IDs

## Monitoring Strategy

### Metrics (Prometheus)

- Sync success/failure rates
- API request latency
- Webhook processing duration
- GitHub workflow execution metrics
- Resource counts by type and status

### Dashboards (Grafana)

- **Port.io Sync Health**: Service uptime, sync rates, latency
- **GitHub Actions**: Runner status, queue depth, job duration
- **Infrastructure Inventory**: Resource counts, health distribution

### Alerts (Alertmanager)

- **Critical**: Exporter down, high failure rate, signature verification failures
- **Warning**: High latency, rate limit approaching, queue depth
- **Info**: New version deployed, configuration changes

## Performance Characteristics

### Throughput

- **Sync Operations**: 50 events/second peak
- **Webhook Requests**: 10 requests/second peak
- **GitHub Workflows**: 20 concurrent executions

### Latency

- **Sync Latency**: P95 < 5 seconds
- **Webhook Processing**: P95 < 200ms
- **End-to-End Provisioning**: 10-15 minutes (dev), 15-30 minutes (prod)

### Scalability

- **Horizontal Scaling**: Exporter and webhook receiver support HPA
- **Resource Limits**: Supports 500+ resources per environment
- **Growth Headroom**: 5,000 entities within 12 months

## Deployment Strategy

### Environment Progression

1. **Dev**: Auto-merge, rapid iteration
2. **Staging**: Manual approval, pre-prod validation
3. **Production**: Manual approval + security review

### Rollout Plan

- **Phase 1** (Weeks 1-2): Read-only sync (dev)
- **Phase 2** (Weeks 3-4): Self-service (dev)
- **Phase 3** (Weeks 5-6): Expand resource types
- **Phase 4** (Weeks 7-8): Production readiness

### Rollback Procedures

- **Disable webhooks**: Stop accepting new requests
- **Scale down**: Reduce replicas to 0
- **Complete rollback**: Delete ArgoCD applications

## Technical Decisions (ADRs)

### ADR-001: Self-Hosted GitHub Actions Runners

**Decision**: Deploy runners in EKS vs using GitHub cloud runners

**Rationale**:
- Security: No secrets exposure to GitHub cloud
- Control: Direct network access to cluster
- Cost: Fixed EKS cost vs per-minute billing

### ADR-002: Go for Webhook Receiver

**Decision**: Go vs Python/Node.js

**Rationale**:
- Performance: Compiled, low latency
- Kubernetes Native: Excellent K8s client libraries
- Concurrency: Built-in goroutines for webhook processing

### ADR-003: HMAC Signature Verification

**Decision**: HMAC vs mTLS

**Rationale**:
- Simplicity: Easier setup and maintenance
- Industry Standard: Used by GitHub, Stripe
- Security: Strong authentication without certificate management

---
**Last Updated**: 2025-11-06
**Version**: 1.0
**Maintainer**: Platform Engineering Team
