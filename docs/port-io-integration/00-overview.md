# Port.io + Crossplane Integration Overview

## Executive Summary

This document provides an overview of the Port.io + Crossplane integration for Portal Kombat. The integration enables bidirectional synchronization between Port.io (Developer Portal) and Crossplane (Infrastructure Platform), providing developers with self-service infrastructure provisioning while maintaining GitOps principles and audit trails.

## What is This Integration?

The Port.io + Crossplane integration creates a centralized service catalog that:
- **Displays Infrastructure State**: Real-time visibility into all Crossplane-managed AWS resources
- **Enables Self-Service**: Developers can request infrastructure through Port.io UI
- **Maintains GitOps**: All changes flow through Git for audit and approval
- **Preserves Source of Truth**: Crossplane remains authoritative for infrastructure state

## Business Value

**Time Savings**:
- Infrastructure discovery: 20 minutes → 2 minutes (90% reduction)
- Dependency mapping: 4 hours/week → 0.5 hours/week (automated)
- Change impact assessment: 30 minutes → 5 minutes (83% reduction)

**Risk Reduction**:
- Prevent 2 incidents/month from unknown dependencies
- Visibility into infrastructure relationships before changes
- Clear blast radius assessment for modifications

**Developer Experience**:
- Self-service infrastructure requests via UI (no YAML required)
- Search and discovery of existing resources
- Real-time status updates and health monitoring

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│                         Port.io Cloud                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Service    │  │   Blueprint  │  │   Webhook    │          │
│  │   Catalog    │  │   Builder    │  │   Manager    │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS/Webhooks
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Portal Kombat EKS Cluster                     │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Port.io Kubernetes Exporter                    │ │
│  │  (Watches Crossplane → Syncs to Port.io Catalog)          │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Webhook Receiver                         │ │
│  │  (Port.io Actions → GitHub Actions)                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                             │                                     │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              Self-Hosted GitHub Actions Runners            │ │
│  │  (Generate YAML → Create PRs)                              │ │
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
```

## Key Components

### 1. Port.io Kubernetes Exporter (Read Path)
- **Purpose**: Synchronize Crossplane resource state to Port.io catalog
- **Technology**: Official Helm chart deployed via ArgoCD
- **Sync Direction**: Crossplane → Port.io (one-way)
- **Frequency**: Real-time (event-driven via Kubernetes Watch API)
- **Resources Synced**: S3 Buckets, RDS Databases, VPCs, EKS Clusters

### 2. Port.io GitHub Backend (Write Path)
- **Purpose**: Trigger GitHub Actions workflows directly from Port.io
- **Technology**: Port.io native GitHub integration
- **Security**: GitHub App authentication with fine-grained permissions
- **Action**: Port.io self-service → GitHub workflow dispatch

### 3. Self-Hosted GitHub Actions Runners
- **Purpose**: Generate Crossplane YAML and create PRs
- **Technology**: actions-runner-controller (ARC) in EKS
- **Security**: Ephemeral runners, network-isolated
- **Workflow**: Validate → Generate YAML → Create PR → Notify Port.io

### 4. Port.io Service Catalog
- **Purpose**: Central infrastructure inventory and self-service portal
- **Technology**: Port.io SaaS (Team tier)
- **Features**: Search, filters, dependency graphs, self-service actions

## Data Flow

### Read Flow (Crossplane → Port.io)
```
1. Crossplane creates AWS resource (e.g., S3 bucket)
2. Kubernetes API emits event (Watch API)
3. Port.io exporter receives event
4. Exporter transforms resource to Port.io entity format
5. Exporter calls Port.io API to upsert entity
6. Port.io catalog updated (visible in UI within 5 seconds)
```

### Write Flow (Port.io → Crossplane)
```
1. Developer requests infrastructure via Port.io UI
2. Port.io GitHub backend triggers workflow dispatch (GitHub API)
3. GitHub Actions workflow receives Port.io payload
4. GitHub Actions runner:
   a. Validates request (naming, quotas, etc.)
   b. Generates Crossplane YAML from template
   c. Creates Git branch and Pull Request
   d. Updates Port.io run status
5. (Dev environment: auto-merge) PR merged automatically
6. ArgoCD detects Git change and syncs
7. Crossplane provisions AWS resource
8. Port.io exporter syncs new resource back to catalog (read flow)
```

## Environments

### Development
- **Cluster**: portal-kombat-dev-raiden
- **Namespace**: port-sync-dev
- **Auto-Merge**: Enabled (no manual approval)
- **Purpose**: Testing and validation

### Staging (Future)
- **Cluster**: portal-kombat-staging-eks
- **Namespace**: port-sync-staging
- **Auto-Merge**: Disabled (manual approval required)
- **Purpose**: Pre-production validation

### Production (Future)
- **Cluster**: portal-kombat-prod-eks
- **Namespace**: port-sync-prod
- **Auto-Merge**: Disabled (manual approval required)
- **Purpose**: Production workloads

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2) ✓
- Deploy Port.io Kubernetes exporter to dev
- Configure blueprints for S3 buckets
- Enable read-only sync (Crossplane → Port.io)

### Phase 2: Self-Service (Weeks 3-4)
- Deploy webhook receiver service
- Deploy self-hosted GitHub Actions runners
- Implement S3 bucket provisioning workflow
- Test end-to-end with 2-3 developers

### Phase 3: Expansion (Weeks 5-6)
- Add RDS database blueprints
- Add VPC and networking blueprints
- Enable dev environment auto-merge
- Onboard 10-20 developers

### Phase 4: Production-Ready (Weeks 7-8)
- Add monitoring dashboards and alerts
- Comprehensive testing suite
- Runbooks and troubleshooting guides
- Staging/production deployment preparation

## Security Model

**Authentication**:
- Port.io API: Client ID + Client Secret (stored in Kubernetes Secret)
- GitHub: GitHub App with repository-scoped permissions
- Kubernetes: Service accounts with RBAC

**Network Security**:
- Webhook receiver: TLS with cert-manager
- IP allowlist for Port.io webhooks
- Network policies isolate components

**Data Security**:
- HMAC signature validation on webhooks
- Secrets encrypted at rest in Kubernetes
- Audit logging for all actions

## Monitoring

**Metrics** (Prometheus):
- Sync success/failure rates
- API request latency
- Entity count by type
- Webhook processing time
- GitHub Actions job durations

**Dashboards** (Grafana):
- Port.io Sync Health
- GitHub Actions Runner Status
- Infrastructure Resource Inventory
- API Performance Metrics

**Alerts** (Alertmanager):
- Sync failure rate > 50% for 10 minutes
- Port.io API circuit breaker open
- GitHub runner queue depth > 10
- Memory usage > 80%

## Quick Links

- [Setup Guide](01-setup-guide.md) - Installation and configuration instructions
- [Developer Guide](02-developer-guide.md) - How to use Port.io for infrastructure requests
- [Troubleshooting](03-troubleshooting.md) - Common issues and solutions
- [Architecture](04-architecture.md) - Deep-dive technical architecture

## Glossary

- **Blueprint**: Port.io schema definition for infrastructure entity types
- **Entity**: Port.io catalog item representing an infrastructure resource
- **Exporter**: Service that syncs Kubernetes resources to Port.io
- **Self-Service Action**: Port.io workflow for infrastructure requests
- **Webhook Receiver**: Service that processes Port.io webhook notifications
- **XRD**: Crossplane Composite Resource Definition (user-facing API)
- **Composition**: Crossplane template implementing XRD with cloud resources

## Support

**Documentation**: docs/port-io-integration/
**Runbook**: docs/port-io-integration/03-troubleshooting.md
**Monitoring**: Grafana dashboard "Port.io Sync Health"
**On-Call**: Platform Engineering team

---
**Last Updated**: 2025-11-06
**Version**: 1.0
**Maintainer**: Platform Engineering Team
