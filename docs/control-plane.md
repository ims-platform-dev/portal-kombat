# Portal Kombat as Port.io Control-Plane Backend

**Document Date:** 2025-11-05
**Architecture Status:** Design
**Context:** Portal Kombat EKS cluster serving as execution backend for Port.io Internal Developer Platform

---

## Table of Contents

- [Executive Summary](#executive-summary)
- [Architecture Overview](#architecture-overview)
- [Component Details](#component-details)
- [Integration Patterns](#integration-patterns)
- [Example Workflows](#example-workflows)
- [Deployment Guide](#deployment-guide)
- [Operations & Monitoring](#operations--monitoring)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)

---

## Executive Summary

### Purpose

This document defines the architecture for using Portal Kombat EKS cluster as the **backend control-plane** for Port.io's Internal Developer Platform. The design enables self-service infrastructure provisioning while preserving GitOps principles and maintaining Git as the single source of truth.

### Key Design Decisions

1. **GitOps-First Approach**: All infrastructure changes flow through Git, maintaining audit trail and rollback capability
2. **Port Execution Agent**: Self-hosted Kafka consumer eliminates need for public webhooks
3. **Kubernetes-Native**: Leverage existing EKS, ArgoCD, and Crossplane infrastructure
4. **Internal Webhook Service**: Custom service handles Port actions and commits to Git

### Architecture Summary

```
Port.io (SaaS)
  → Kafka Topic
  → Port Execution Agent (in EKS)
  → GitOps Webhook Service (in EKS)
  → Git Commit (via GitHub API)
  → ArgoCD Sync
  → Crossplane Provisioning
  → AWS Resources
  → Port Ocean Exporter syncs back to Port Catalog
```

---

## Architecture Overview

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Port.io (SaaS Platform)                      │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  Developer Portal                                       │    │
│  │  • Self-service UI (blueprints, actions, catalog)      │    │
│  │  • RBAC & Approval Workflows                           │    │
│  │  • Software Catalog (unified view)                     │    │
│  └────────────────────────────────────────────────────────┘    │
└────────────────────────────┬────────────────────────────────────┘
                             │ Kafka Topic
                             │ (Port provisions dedicated topic)
                             ↓
┌─────────────────────────────────────────────────────────────────┐
│         Portal Kombat EKS Cluster (Control-Plane Backend)        │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Namespace: port-system                                   │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  Port Execution Agent (Helm)                        │  │  │
│  │  │  • Consumes Kafka events                            │  │  │
│  │  │  • Routes to internal webhooks                      │  │  │
│  │  │  • No public internet exposure required             │  │  │
│  │  └────────────────┬───────────────────────────────────┘  │  │
│  │                   │                                        │  │
│  │  ┌────────────────▼───────────────────────────────────┐  │  │
│  │  │  Port Ocean Exporter (Helm)                         │  │  │
│  │  │  • Syncs Crossplane → Port catalog                  │  │  │
│  │  │  • Syncs ArgoCD → Port catalog                      │  │  │
│  │  │  • Syncs Kubernetes → Port catalog                  │  │  │
│  │  │  • Bi-directional state synchronization             │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Namespace: port-gitops                                   │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │  GitOps Webhook Service (Custom)                    │  │  │
│  │  │  • Receives Port action webhooks                    │  │  │
│  │  │  • Validates inputs & generates manifests           │  │  │
│  │  │  • Commits to Git via GitHub API                    │  │  │
│  │  │  • Reports status to Port API                       │  │  │
│  │  │  • Language: Python (FastAPI) or Go                 │  │  │
│  │  └────────────────┬───────────────────────────────────┘  │  │
│  └───────────────────┼──────────────────────────────────────┘  │
│                      │                                           │
│  ┌───────────────────▼──────────────────────────────────────┐  │
│  │  Existing Components (ArgoCD + Crossplane)               │  │
│  │  • ArgoCD: GitOps operator (watches Git)                │  │
│  │  • Crossplane: IaC operator (provisions AWS)            │  │
│  │  • cert-manager, external-dns, nginx-ingress, etc.      │  │
│  └──────────────────────────────────────────────────────────┘  │
└───────────────────────────┬───────────────────────────────────┘
                            │ commits via GitHub API
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│               Git Repository (portal-kombat)                     │
│  environments/                                                   │
│    dev/infrastructure/storage/my-bucket.yaml                    │
│    staging/infrastructure/databases/my-db.yaml                  │
│    prod/infrastructure/compute/my-cluster.yaml                  │
└────────────────────────────┬────────────────────────────────────┘
                             │ ArgoCD watches
                             ↓
                        (back to EKS ArgoCD)
                             ↓
                        Crossplane provisions
                             ↓
                      ┌─────────────┐
                      │     AWS      │
                      │  S3, RDS,    │
                      │  EKS, VPC    │
                      └─────────────┘
```

### Design Principles

1. **GitOps Preservation**: All infrastructure changes committed to Git before execution
2. **Single Source of Truth**: Git repository remains authoritative for infrastructure state
3. **Self-Healing**: Crossplane and ArgoCD continuously reconcile desired state
4. **Audit Trail**: Every change traceable through Git history
5. **Rollback Capability**: Git revert enables infrastructure rollback
6. **No Public Exposure**: Port Execution Agent uses Kafka (pull model), no inbound internet required

---

## Component Details

### 1. Port Execution Agent

**Purpose**: Self-hosted Kafka consumer that receives Port action events and routes them to internal cluster services without requiring public webhook endpoints.

#### Architecture

```
Port SaaS Platform
        ↓ publishes event
Kafka Topic (Port-managed)
        ↓ agent polls
Port Execution Agent Pod (in EKS)
        ↓ HTTP POST
Internal Webhook Service (in EKS)
```

#### Deployment Specification

**Namespace**: `port-system`

**Helm Installation**:
```bash
# Prerequisites:
# 1. Contact Port support (support@getport.io) to provision dedicated Kafka topic
# 2. Receive Kafka bootstrap servers and topic name
# 3. Obtain Port API credentials (client ID + secret)

# Add Port Helm repository
helm repo add port-labs https://port-labs.github.io/helm-charts
helm repo update

# Install Port Execution Agent
helm install port-agent port-labs/port-agent \
  --namespace port-system \
  --create-namespace \
  --set kafka.bootstrapServers="<PORT_PROVIDED_KAFKA_ENDPOINT>" \
  --set kafka.topic="<PORT_PROVIDED_TOPIC_NAME>" \
  --set kafka.consumerGroup="portal-kombat-control-plane" \
  --set kafka.authentication.enabled=true \
  --set kafka.authentication.mechanism="SCRAM-SHA-512" \
  --set kafka.authentication.username="<PORT_PROVIDED_USERNAME>" \
  --set kafka.authentication.password="<PORT_PROVIDED_PASSWORD>" \
  --set webhook.url="http://gitops-webhook.port-gitops.svc.cluster.local:8080" \
  --set port.clientId="${PORT_CLIENT_ID}" \
  --set port.clientSecret="${PORT_CLIENT_SECRET}"
```

**Custom Values** (`port-agent-values.yaml`):
```yaml
replicaCount: 2  # High availability

kafka:
  bootstrapServers: "<PORT_PROVIDED_KAFKA_ENDPOINT>"
  topic: "<PORT_PROVIDED_TOPIC_NAME>"
  consumerGroup: "portal-kombat-control-plane"
  authentication:
    enabled: true
    mechanism: "SCRAM-SHA-512"
    username: "<PORT_PROVIDED_USERNAME>"
    password: "<PORT_PROVIDED_PASSWORD>"
  ssl:
    enabled: true

webhook:
  url: "http://gitops-webhook.port-gitops.svc.cluster.local:8080"
  timeout: 30s
  retryPolicy:
    attempts: 3
    backoff: exponential

port:
  clientId: "${PORT_CLIENT_ID}"
  clientSecret: "${PORT_CLIENT_SECRET}"
  baseUrl: "https://api.getport.io"  # or https://api.us.getport.io for US region

resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "500m"

podAnnotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9090"
  prometheus.io/path: "/metrics"
```

#### Configuration

**Service Account**: `port-agent`
- No AWS permissions required (agent doesn't interact with AWS directly)
- Only needs Kubernetes API access for health checks

**Security Context**:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  capabilities:
    drop:
      - ALL
```

#### Monitoring

**Health Endpoints**:
- `/health/liveness`: Agent process running
- `/health/readiness`: Kafka connection established
- `/metrics`: Prometheus metrics

**Key Metrics**:
- `port_agent_kafka_messages_consumed_total`: Total Kafka events processed
- `port_agent_webhook_requests_total`: Webhooks sent to internal services
- `port_agent_webhook_errors_total`: Failed webhook deliveries
- `port_agent_kafka_lag`: Consumer lag on Kafka topic

---

### 2. Port Ocean Exporter

**Purpose**: Continuously syncs Kubernetes resources (Crossplane, ArgoCD, standard K8s) to Port's software catalog, providing real-time visibility into infrastructure state.

#### Architecture

```
Kubernetes API Server
        ↓ watch/list
Port Ocean Exporter (in EKS)
        ↓ syncs via HTTP
Port API (SaaS)
        ↓ creates/updates
Port Software Catalog
```

#### Deployment Specification

**Namespace**: `port-system`

**Helm Installation**:
```bash
# Install Port Kubernetes Exporter
helm install k8s-exporter port-labs/port-ocean \
  --namespace port-system \
  --set port.clientId="${PORT_CLIENT_ID}" \
  --set port.clientSecret="${PORT_CLIENT_SECRET}" \
  --set port.baseUrl="https://api.getport.io" \
  --set integration.type="kubernetes" \
  --set integration.config.clusterName="portal-kombat-dev" \
  -f ocean-exporter-config.yaml
```

**Custom Configuration** (`ocean-exporter-config.yaml`):
```yaml
integration:
  config:
    resources:
      # Crossplane Bucket resources
      - kind: s3.aws.upbound.io/v1beta1/bucket
        selector:
          query: 'true'
        port:
          entity:
            mappings:
              identifier: .metadata.name
              title: .metadata.name
              blueprint: '"s3Bucket"'
              properties:
                region: .spec.forProvider.region
                versioning: .spec.forProvider.versioning[0].enabled
                status: .status.conditions[0].status
                syncStatus: .status.conditions[0].reason
                createdAt: .metadata.creationTimestamp
                owner: .metadata.labels["owner"]
                managedBy: .metadata.labels["managed-by"]
              relations:
                environment: .metadata.labels["environment"]

      # Crossplane ObjectStorage Claims (custom XRD)
      - kind: aws.platform.example/v1alpha1/objectstorage
        selector:
          query: 'true'
        port:
          entity:
            mappings:
              identifier: .metadata.name
              title: .spec.parameters.bucketName
              blueprint: '"s3Bucket"'
              properties:
                bucketName: .spec.parameters.bucketName
                region: .spec.parameters.region
                versioning: .spec.parameters.versioning
                status: .status.conditions[0].status
                owner: .metadata.labels["owner"]
              relations:
                environment: .metadata.labels["environment"]

      # ArgoCD Applications
      - kind: argoproj.io/v1alpha1/application
        selector:
          query: '.metadata.namespace == "argocd"'
        port:
          entity:
            mappings:
              identifier: .metadata.name
              title: .metadata.name
              blueprint: '"argocdApplication"'
              properties:
                syncStatus: .status.sync.status
                healthStatus: .status.health.status
                repoURL: .spec.source.repoURL
                path: .spec.source.path
                targetRevision: .spec.source.targetRevision
                destination: .spec.destination.server
                namespace: .spec.destination.namespace
              relations:
                cluster: '"portal-kombat-dev"'

      # Kubernetes Namespaces
      - kind: v1/namespace
        selector:
          query: '.metadata.name | startswith("prod-") or startswith("dev-") or startswith("staging-")'
        port:
          entity:
            mappings:
              identifier: .metadata.name
              title: .metadata.name
              blueprint: '"namespace"'
              properties:
                status: .status.phase
                createdAt: .metadata.creationTimestamp
              relations:
                cluster: '"portal-kombat-dev"'

resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "500m"

serviceAccount:
  create: true
  name: port-ocean-exporter

rbac:
  create: true
  rules:
    - apiGroups: ["*"]
      resources: ["*"]
      verbs: ["get", "list", "watch"]
```

#### Port Blueprints

Before deploying the exporter, create these blueprints in Port UI:

**S3 Bucket Blueprint**:
```json
{
  "identifier": "s3Bucket",
  "title": "S3 Bucket",
  "schema": {
    "properties": {
      "bucketName": {"type": "string", "title": "Bucket Name"},
      "region": {"type": "string", "title": "AWS Region"},
      "versioning": {"type": "boolean", "title": "Versioning Enabled"},
      "status": {"type": "string", "title": "Status", "enum": ["True", "False", "Unknown"]},
      "syncStatus": {"type": "string", "title": "Sync Status"},
      "owner": {"type": "string", "title": "Owner"},
      "managedBy": {"type": "string", "title": "Managed By"},
      "createdAt": {"type": "string", "format": "date-time", "title": "Created At"}
    }
  },
  "relations": {
    "environment": {
      "target": "environment",
      "title": "Environment",
      "many": false,
      "required": false
    }
  }
}
```

**ArgoCD Application Blueprint**:
```json
{
  "identifier": "argocdApplication",
  "title": "ArgoCD Application",
  "schema": {
    "properties": {
      "syncStatus": {"type": "string", "title": "Sync Status"},
      "healthStatus": {"type": "string", "title": "Health Status"},
      "repoURL": {"type": "string", "title": "Repository URL"},
      "path": {"type": "string", "title": "Path"},
      "targetRevision": {"type": "string", "title": "Target Revision"},
      "destination": {"type": "string", "title": "Destination Server"},
      "namespace": {"type": "string", "title": "Namespace"}
    }
  },
  "relations": {
    "cluster": {
      "target": "cluster",
      "title": "Cluster",
      "many": false,
      "required": false
    }
  }
}
```

---

### 3. GitOps Webhook Service

**Purpose**: Custom service that receives Port action webhooks, validates inputs, generates Crossplane manifests, and commits them to Git via GitHub API.

#### Architecture

```
Port Execution Agent
        ↓ HTTP POST /provision-s3-bucket
GitOps Webhook Service
        ↓
  1. Validate inputs
  2. Generate Crossplane manifest
  3. Commit to Git (GitHub API)
  4. Report status to Port API
        ↓
GitHub Repository (portal-kombat)
```

#### Technology Stack Options

**Option A: Python + FastAPI** (Recommended for rapid development)
- **Pros**: Rich ecosystem, easy Jinja2 templating, extensive GitHub API libraries
- **Cons**: Higher memory footprint, Python runtime management
- **Libraries**: FastAPI, PyGithub, Jinja2, pydantic

**Option B: Go + net/http**
- **Pros**: Better performance, smaller container image, Kubernetes-native
- **Cons**: More verbose templating, longer development time
- **Libraries**: github.com/google/go-github, text/template

#### Service Architecture

**Namespace**: `port-gitops`

**Deployment Structure**:
```
port-gitops/
├── deployment.yaml      # Kubernetes Deployment
├── service.yaml         # ClusterIP Service
├── configmap.yaml       # Configuration (templates, GitHub repo)
├── secret.yaml          # GitHub PAT, Port API credentials
└── serviceaccount.yaml  # Service Account (no special permissions)
```

#### Python FastAPI Implementation

**Project Structure**:
```
gitops-webhook-service/
├── app/
│   ├── main.py              # FastAPI application
│   ├── models.py            # Pydantic models
│   ├── handlers/
│   │   ├── s3_bucket.py     # S3 bucket provisioning
│   │   ├── rds_database.py  # RDS database provisioning
│   │   └── eks_cluster.py   # EKS cluster provisioning
│   ├── git/
│   │   ├── client.py        # GitHub API client
│   │   └── operations.py    # Git operations
│   ├── port/
│   │   └── client.py        # Port API client
│   └── templates/
│       ├── s3-bucket.yaml.j2
│       ├── rds-database.yaml.j2
│       └── eks-cluster.yaml.j2
├── Dockerfile
├── requirements.txt
└── tests/
```

**Core Implementation** (`app/main.py`):
```python
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from typing import Dict, Any, Optional
import logging
from github import Github
from jinja2 import Environment, FileSystemLoader
import yaml
import os
import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Portal Kombat GitOps Webhook Service")

# Configuration
GITHUB_TOKEN = os.environ["GITHUB_TOKEN"]
GITHUB_REPO = os.environ.get("GITHUB_REPO", "your-org/portal-kombat")
PORT_CLIENT_ID = os.environ["PORT_CLIENT_ID"]
PORT_CLIENT_SECRET = os.environ["PORT_CLIENT_SECRET"]
PORT_API_BASE = os.environ.get("PORT_API_BASE", "https://api.getport.io")

# Initialize clients
github_client = Github(GITHUB_TOKEN)
repo = github_client.get_repo(GITHUB_REPO)
jinja_env = Environment(loader=FileSystemLoader("templates"))

class PortActionRequest(BaseModel):
    action: str
    run_id: str
    user: str
    inputs: Dict[str, Any]
    port_context: Optional[Dict[str, Any]] = {}

def update_port_run(run_id: str, status: str, message: str):
    """Report action status back to Port API"""
    auth_response = requests.post(
        f"{PORT_API_BASE}/v1/auth/access_token",
        json={"clientId": PORT_CLIENT_ID, "clientSecret": PORT_CLIENT_SECRET}
    )
    token = auth_response.json()["accessToken"]

    requests.patch(
        f"{PORT_API_BASE}/v1/actions/runs/{run_id}",
        headers={"Authorization": f"Bearer {token}"},
        json={"status": status, "logMessage": message}
    )

def generate_manifest(template_name: str, context: Dict[str, Any]) -> str:
    """Generate Crossplane manifest from Jinja2 template"""
    template = jinja_env.get_template(template_name)
    return template.render(**context)

def commit_to_git(file_path: str, content: str, commit_message: str, branch: str = "main"):
    """Commit file to GitHub repository"""
    try:
        # Try to get existing file for updates
        try:
            existing_file = repo.get_contents(file_path, ref=branch)
            repo.update_file(
                path=file_path,
                message=commit_message,
                content=content,
                sha=existing_file.sha,
                branch=branch
            )
        except:
            # File doesn't exist, create new
            repo.create_file(
                path=file_path,
                message=commit_message,
                content=content,
                branch=branch
            )
        return True
    except Exception as e:
        logger.error(f"Failed to commit to Git: {e}")
        raise

@app.post("/provision-s3-bucket")
async def provision_s3_bucket(request: PortActionRequest):
    """Handle S3 bucket provisioning action"""
    logger.info(f"Provisioning S3 bucket: {request.inputs}")

    try:
        # Update Port: Starting
        update_port_run(
            request.run_id,
            "IN_PROGRESS",
            "🔄 Generating Crossplane manifest..."
        )

        # Validate inputs
        bucket_name = request.inputs["bucket_name"]
        environment = request.inputs["environment"]
        region = request.inputs.get("region", "us-east-2")
        versioning = request.inputs.get("versioning", True)

        # Validate bucket name pattern
        if not bucket_name.startswith("portal-kombat-"):
            raise HTTPException(
                status_code=400,
                detail="Bucket name must start with 'portal-kombat-'"
            )

        # Generate manifest
        manifest_content = generate_manifest("s3-bucket.yaml.j2", {
            "name": f"{bucket_name}-bucket",
            "bucket_name": f"{bucket_name}-{environment}",
            "region": region,
            "versioning": versioning,
            "environment": environment,
            "owner": request.user,
            "managed_by": "port"
        })

        # Commit to Git
        file_path = f"environments/{environment}/infrastructure/storage/{bucket_name}.yaml"
        commit_message = f"""[Port] Create S3 bucket {bucket_name} for {environment}

Triggered by: {request.user}
Port Run ID: {request.run_id}
Action: provision-s3-bucket
"""

        update_port_run(
            request.run_id,
            "IN_PROGRESS",
            "📝 Committing manifest to Git..."
        )

        commit_to_git(file_path, manifest_content, commit_message)

        # Update Port: Success
        update_port_run(
            request.run_id,
            "SUCCESS",
            f"""✅ S3 bucket provisioning initiated successfully!

📁 **File**: `{file_path}`
🌍 **Region**: {region}
🔄 **Versioning**: {versioning}
📦 **Environment**: {environment}

**Next Steps**:
1. ArgoCD will sync within 3 minutes
2. Crossplane will provision bucket in AWS (~2-5 minutes)
3. Bucket will appear in Port catalog when ready

Track in Git: https://github.com/{GITHUB_REPO}/blob/main/{file_path}
"""
        )

        return {
            "status": "success",
            "file_path": file_path,
            "message": "Manifest committed to Git. ArgoCD will sync shortly."
        }

    except Exception as e:
        logger.error(f"Error provisioning S3 bucket: {e}")
        update_port_run(
            request.run_id,
            "FAILURE",
            f"❌ Failed to provision S3 bucket: {str(e)}"
        )
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "gitops-webhook"}

@app.get("/readiness")
async def readiness_check():
    """Readiness check - verify GitHub and Port API connectivity"""
    try:
        # Test GitHub API
        repo.get_branch("main")
        # Test Port API
        auth_response = requests.post(
            f"{PORT_API_BASE}/v1/auth/access_token",
            json={"clientId": PORT_CLIENT_ID, "clientSecret": PORT_CLIENT_SECRET}
        )
        if auth_response.status_code == 200:
            return {"status": "ready"}
        else:
            return {"status": "not_ready", "reason": "Port API auth failed"}
    except Exception as e:
        return {"status": "not_ready", "reason": str(e)}
```

**Jinja2 Template** (`templates/s3-bucket.yaml.j2`):
```yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage
metadata:
  name: {{ name }}
  labels:
    environment: {{ environment }}
    managed-by: {{ managed_by }}
    owner: {{ owner }}
    provisioned-via: port.io
spec:
  parameters:
    bucketName: portal-kombat-{{ environment }}-{{ bucket_name }}
    region: {{ region }}
    versioning: {{ versioning|lower }}
```

**Dockerfile**:
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY app/ ./app/

# Non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**requirements.txt**:
```
fastapi==0.104.1
uvicorn[standard]==0.24.0
PyGithub==2.1.1
Jinja2==3.1.2
pydantic==2.5.0
requests==2.31.0
PyYAML==6.0.1
```

#### Kubernetes Deployment

**Deployment** (`k8s/deployment.yaml`):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-webhook
  namespace: port-gitops
  labels:
    app: gitops-webhook
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gitops-webhook
  template:
    metadata:
      labels:
        app: gitops-webhook
    spec:
      serviceAccountName: gitops-webhook
      containers:
      - name: webhook
        image: your-registry/gitops-webhook:latest
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: GITHUB_TOKEN
          valueFrom:
            secretKeyRef:
              name: gitops-webhook-secrets
              key: github-token
        - name: GITHUB_REPO
          value: "your-org/portal-kombat"
        - name: PORT_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: gitops-webhook-secrets
              key: port-client-id
        - name: PORT_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: gitops-webhook-secrets
              key: port-client-secret
        - name: PORT_API_BASE
          value: "https://api.getport.io"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

**Service** (`k8s/service.yaml`):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: gitops-webhook
  namespace: port-gitops
spec:
  selector:
    app: gitops-webhook
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
  type: ClusterIP
```

**Secret** (`k8s/secret.yaml`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: gitops-webhook-secrets
  namespace: port-gitops
type: Opaque
stringData:
  github-token: "<GITHUB_PAT_WITH_REPO_WRITE_ACCESS>"
  port-client-id: "<PORT_CLIENT_ID>"
  port-client-secret: "<PORT_CLIENT_SECRET>"
```

---

## Integration Patterns

### Pattern 1: Infrastructure Provisioning (CREATE Actions)

**Use Case**: Developer provisions new AWS infrastructure (S3 bucket, RDS database, EKS cluster)

**Flow**:
1. Developer triggers Port action via UI
2. Port publishes event to Kafka topic
3. Port Execution Agent consumes event
4. Agent forwards to GitOps Webhook Service
5. Service generates Crossplane manifest
6. Service commits manifest to Git via GitHub API
7. ArgoCD detects Git change (within 3 minutes or via webhook)
8. ArgoCD syncs manifest to cluster
9. Crossplane reconciles and provisions AWS resource
10. Port Ocean Exporter syncs resource status to Port catalog
11. Developer sees resource in Port catalog with status

**Example Port Action Definition**:
```json
{
  "identifier": "provision_s3_bucket",
  "title": "Provision S3 Bucket",
  "icon": "Bucket",
  "description": "Creates a new S3 bucket using Crossplane",
  "trigger": {
    "type": "self-service",
    "operation": "CREATE",
    "blueprintIdentifier": "s3Bucket",
    "userInputs": {
      "properties": {
        "bucket_name": {
          "title": "Bucket Name",
          "type": "string",
          "pattern": "^[a-z0-9-]+$",
          "description": "Bucket name (will be prefixed with portal-kombat-{env}-)"
        },
        "environment": {
          "title": "Environment",
          "type": "string",
          "enum": ["dev", "staging", "prod"],
          "default": "dev"
        },
        "region": {
          "title": "AWS Region",
          "type": "string",
          "enum": ["us-east-1", "us-east-2", "us-west-2"],
          "default": "us-east-2"
        },
        "versioning": {
          "title": "Enable Versioning",
          "type": "boolean",
          "default": true
        }
      },
      "required": ["bucket_name", "environment"]
    }
  },
  "invocationMethod": {
    "type": "WEBHOOK",
    "url": "http://gitops-webhook.port-gitops.svc.cluster.local:8080/provision-s3-bucket",
    "agent": true,
    "synchronized": false,
    "method": "POST"
  },
  "requiredApproval": false
}
```

### Pattern 2: Day-2 Operations (Operational Actions)

**Use Case**: Restart failed pods, scale deployments, trigger ArgoCD sync

**Flow**:
1. Developer triggers operational action in Port
2. Port publishes event to Kafka
3. Port Execution Agent forwards to operations webhook
4. Operations service executes `kubectl` commands directly
5. No Git commit required (operational, not declarative infrastructure)
6. Service reports status back to Port
7. Port Ocean Exporter syncs updated state

**Example**: Restart Deployment
```python
@app.post("/restart-deployment")
async def restart_deployment(request: PortActionRequest):
    """Restart a Kubernetes deployment"""
    namespace = request.inputs["namespace"]
    deployment = request.inputs["deployment"]

    # Execute kubectl rollout restart
    subprocess.run([
        "kubectl", "rollout", "restart",
        f"deployment/{deployment}",
        "-n", namespace
    ], check=True)

    update_port_run(
        request.run_id,
        "SUCCESS",
        f"✅ Deployment {deployment} restarted in namespace {namespace}"
    )
```

### Pattern 3: Deletion Actions

**Use Case**: Delete infrastructure resources

**Flow**:
1. Developer triggers delete action
2. GitOps service deletes file from Git
3. ArgoCD syncs (removes resource from cluster)
4. Crossplane deletes AWS resource
5. Port Ocean detects deletion and removes from catalog

**Important**: Implement soft-delete with confirmation to prevent accidental deletions.

---

## Example Workflows

### Workflow 1: Developer Provisions S3 Bucket (Complete Lifecycle)

#### Step 1: Port Action Configuration

Create action in Port UI:
- **Blueprint**: s3Bucket
- **Operation**: CREATE
- **Inputs**: bucket_name, environment, region, versioning
- **Backend**: Webhook to Port Execution Agent

#### Step 2: Developer Triggers Action

Developer goes to Port UI:
1. Navigate to "Self-Service Actions"
2. Click "Provision S3 Bucket"
3. Fill form:
   - **Bucket Name**: `analytics-data`
   - **Environment**: `dev`
   - **Region**: `us-east-2`
   - **Versioning**: `true`
4. Click "Execute"

#### Step 3: Port → Kafka → Agent

Port publishes to Kafka:
```json
{
  "action": "provision_s3_bucket",
  "run_id": "r_abc123",
  "user": "alice@company.com",
  "inputs": {
    "bucket_name": "analytics-data",
    "environment": "dev",
    "region": "us-east-2",
    "versioning": true
  }
}
```

Port Execution Agent consumes event and forwards:
```
POST http://gitops-webhook.port-gitops.svc.cluster.local:8080/provision-s3-bucket
```

#### Step 4: GitOps Service → Git Commit

GitOps webhook service:
1. Validates inputs
2. Generates manifest:
```yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage
metadata:
  name: analytics-data-bucket
  labels:
    environment: dev
    managed-by: port
    owner: alice@company.com
spec:
  parameters:
    bucketName: portal-kombat-dev-analytics-data
    region: us-east-2
    versioning: true
```

3. Commits to Git:
```
File: environments/dev/infrastructure/storage/analytics-data.yaml
Commit: "[Port] Create S3 bucket analytics-data for dev
         Triggered by: alice@company.com
         Port Run ID: r_abc123"
```

4. Reports to Port:
```
Status: SUCCESS
Message: "✅ Manifest committed to Git. ArgoCD will sync within 3 minutes."
```

#### Step 5: ArgoCD Sync

ArgoCD (within 3 minutes):
1. Detects new file in Git
2. Syncs to cluster
3. Creates `ObjectStorage` claim

#### Step 6: Crossplane Provisioning

Crossplane:
1. Detects new `ObjectStorage` claim
2. Uses composition to generate AWS `Bucket` resource
3. Provisions S3 bucket in AWS (2-5 minutes)
4. Updates claim status to "Ready"

#### Step 7: Port Catalog Update

Port Ocean Exporter:
1. Watches Crossplane resources
2. Detects new `ObjectStorage` with status "Ready"
3. Syncs to Port catalog as `s3Bucket` entity
4. Developer sees bucket in Port UI with full metadata

#### Timeline
- **T+0s**: Action triggered in Port
- **T+2s**: Manifest committed to Git
- **T+3min**: ArgoCD syncs to cluster
- **T+5min**: Crossplane provisions in AWS
- **T+6min**: Bucket appears in Port catalog

---

### Workflow 2: Day-2 Operation - Restart Failed Application

#### Scenario
Application pods are in CrashLoopBackOff due to transient issue. Platform team wants to provide self-service restart capability.

#### Port Action Configuration
```json
{
  "identifier": "restart_deployment",
  "title": "Restart Deployment",
  "icon": "Reload",
  "trigger": {
    "type": "self-service",
    "operation": "DAY_2",
    "blueprintIdentifier": "deployment",
    "userInputs": {
      "properties": {
        "namespace": {
          "title": "Namespace",
          "type": "string"
        },
        "deployment": {
          "title": "Deployment Name",
          "type": "string"
        }
      },
      "required": ["namespace", "deployment"]
    }
  },
  "invocationMethod": {
    "type": "WEBHOOK",
    "url": "http://operations-service.port-gitops.svc.cluster.local:8080/restart-deployment",
    "agent": true,
    "synchronized": true
  }
}
```

#### Execution Flow
1. Developer selects failing deployment in Port catalog
2. Clicks "Restart Deployment" day-2 action
3. Port → Kafka → Agent → Operations Service
4. Operations service executes:
```bash
kubectl rollout restart deployment/my-app -n production
```
5. Service reports success to Port
6. Port Ocean syncs updated pod status
7. Developer sees pods restarting in real-time in catalog

**No Git commit required** - this is an operational action, not infrastructure state change.

---

## Deployment Guide

### Prerequisites

1. **Portal Kombat EKS Cluster**: Existing cluster with ArgoCD and Crossplane installed
2. **Port.io Account**: Active Port.io account with API credentials
3. **Kafka Topic**: Contact Port support to provision dedicated Kafka topic
4. **GitHub PAT**: Personal Access Token with `repo` write access
5. **ArgoCD Access**: Admin access to ArgoCD for application creation

### Phase 1: Port Setup (Week 1)

#### Step 1.1: Create Port Blueprints

In Port UI (https://app.getport.io), create blueprints:

**S3 Bucket Blueprint** (copy JSON from Component Details section)
**ArgoCD Application Blueprint** (copy JSON from Component Details section)
**Environment Blueprint**:
```json
{
  "identifier": "environment",
  "title": "Environment",
  "schema": {
    "properties": {
      "type": {"type": "string", "enum": ["dev", "staging", "prod"]},
      "region": {"type": "string"}
    }
  }
}
```

#### Step 1.2: Request Kafka Topic

Email Port support (support@getport.io):
```
Subject: Kafka Topic Request for Portal Kombat Control Plane

We'd like to use Port's Execution Agent for self-hosted action execution.

Organization: <Your Org>
Use Case: GitOps control plane for Crossplane infrastructure
Estimated Event Volume: ~100 actions/day

Please provision a dedicated Kafka topic and provide:
- Kafka bootstrap servers
- Topic name
- Authentication credentials (SCRAM-SHA-512)
```

Expected response time: 1-2 business days

#### Step 1.3: Obtain Port API Credentials

In Port UI:
1. Go to Settings → API Tokens
2. Create new token: "Portal Kombat Control Plane"
3. Save `clientId` and `clientSecret`

### Phase 2: Deploy Port Components (Week 1-2)

#### Step 2.1: Create Namespaces

```bash
kubectl create namespace port-system
kubectl create namespace port-gitops
```

#### Step 2.2: Deploy Port Execution Agent

Create secrets:
```bash
kubectl create secret generic port-agent-secrets \
  --namespace port-system \
  --from-literal=port-client-id="${PORT_CLIENT_ID}" \
  --from-literal=port-client-secret="${PORT_CLIENT_SECRET}" \
  --from-literal=kafka-username="${KAFKA_USERNAME}" \
  --from-literal=kafka-password="${KAFKA_PASSWORD}"
```

Install Helm chart:
```bash
helm repo add port-labs https://port-labs.github.io/helm-charts
helm repo update

helm install port-agent port-labs/port-agent \
  --namespace port-system \
  --values port-agent-values.yaml
```

Verify deployment:
```bash
kubectl get pods -n port-system
kubectl logs -n port-system -l app=port-agent --tail=50
```

Expected logs:
```
INFO: Connected to Kafka broker
INFO: Subscribed to topic: portal-kombat-actions
INFO: Webhook target: http://gitops-webhook.port-gitops.svc.cluster.local:8080
INFO: Agent ready to process events
```

#### Step 2.3: Deploy Port Ocean Exporter

Install Helm chart:
```bash
helm install k8s-exporter port-labs/port-ocean \
  --namespace port-system \
  --values ocean-exporter-config.yaml
```

Verify sync:
```bash
kubectl logs -n port-system -l app=port-ocean-exporter --tail=50
```

Check Port UI - should see existing Crossplane resources syncing to catalog.

### Phase 3: Deploy GitOps Webhook Service (Week 2)

#### Step 3.1: Build Container Image

```bash
cd gitops-webhook-service
docker build -t your-registry/gitops-webhook:v1.0.0 .
docker push your-registry/gitops-webhook:v1.0.0
```

#### Step 3.2: Create Secrets

```bash
kubectl create secret generic gitops-webhook-secrets \
  --namespace port-gitops \
  --from-literal=github-token="${GITHUB_PAT}" \
  --from-literal=port-client-id="${PORT_CLIENT_ID}" \
  --from-literal=port-client-secret="${PORT_CLIENT_SECRET}"
```

#### Step 3.3: Deploy Service

```bash
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Verify:
```bash
kubectl get pods -n port-gitops
kubectl logs -n port-gitops -l app=gitops-webhook --tail=50

# Test health endpoint
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://gitops-webhook.port-gitops.svc.cluster.local:8080/health
```

Expected response:
```json
{"status": "healthy", "service": "gitops-webhook"}
```

### Phase 4: Configure Port Actions (Week 2-3)

#### Step 4.1: Create "Provision S3 Bucket" Action

In Port UI:
1. Go to Self-Service Actions
2. Click "New Action"
3. Copy JSON definition from Integration Patterns section
4. Update webhook URL if needed
5. Save and test

#### Step 4.2: Test End-to-End Flow

1. Trigger action in Port UI
2. Monitor logs:
```bash
# Port Agent logs
kubectl logs -n port-system -l app=port-agent -f

# GitOps Webhook logs
kubectl logs -n port-gitops -l app=gitops-webhook -f

# ArgoCD sync
kubectl get applications -n argocd -w

# Crossplane provisioning
kubectl get objectstorage -w
kubectl get bucket -w
```

3. Verify Git commit in GitHub
4. Verify bucket in AWS console
5. Verify entity in Port catalog

### Phase 5: Add Additional Actions (Week 3-4)

Implement additional handlers in GitOps webhook service:
- RDS Database provisioning
- EKS Cluster provisioning
- VPC network provisioning
- Day-2 operations (restart, scale, rollback)

---

## Operations & Monitoring

### Observability Stack

**Metrics Collection**:
- Port Execution Agent: Prometheus metrics on `:9090/metrics`
- GitOps Webhook Service: Custom metrics via Prometheus client library
- Port Ocean Exporter: Built-in Prometheus metrics

**Key Metrics to Monitor**:

```prometheus
# Port Execution Agent
port_agent_kafka_messages_consumed_total
port_agent_kafka_consumer_lag
port_agent_webhook_requests_total{status="success|failure"}
port_agent_webhook_latency_seconds

# GitOps Webhook Service
gitops_webhook_requests_total{handler="provision_s3_bucket", status="success|failure"}
gitops_webhook_git_commits_total{status="success|failure"}
gitops_webhook_port_api_calls_total{operation="update_run", status="success|failure"}
gitops_webhook_request_duration_seconds{handler="provision_s3_bucket"}

# Port Ocean Exporter
port_ocean_resources_synced_total{kind="bucket"}
port_ocean_sync_errors_total
port_ocean_sync_duration_seconds
```

**Grafana Dashboards**:

Create dashboard with panels:
1. **Action Execution Rate**: Requests per minute
2. **Success Rate**: Percentage of successful actions
3. **Kafka Consumer Lag**: Agent lag on Kafka topic
4. **Git Commit Rate**: Commits per hour
5. **Port API Latency**: Response times for Port API calls
6. **Error Rate**: Failed actions per minute

### Logging

**Structured Logging Format** (JSON):
```json
{
  "timestamp": "2025-01-05T10:23:45Z",
  "level": "INFO",
  "service": "gitops-webhook",
  "handler": "provision_s3_bucket",
  "action_id": "provision_s3_bucket",
  "run_id": "r_abc123",
  "user": "alice@company.com",
  "message": "Manifest committed to Git",
  "file_path": "environments/dev/infrastructure/storage/analytics-data.yaml",
  "duration_ms": 1250
}
```

**Log Aggregation**:
- Use FluentBit/Fluentd to collect logs from pods
- Ship to CloudWatch Logs, Elasticsearch, or Loki
- Create alerts for error patterns

**Key Log Queries**:
```
# Failed actions in last hour
level="ERROR" service="gitops-webhook" | count by handler

# Slow operations (>5s)
duration_ms > 5000 | avg(duration_ms) by handler

# Port API errors
message="Port API call failed" | count
```

### Alerts

**Critical Alerts** (PagerDuty):
```yaml
# Port Agent down
alert: PortAgentDown
expr: up{job="port-agent"} == 0
for: 2m
severity: critical

# High error rate
alert: HighActionFailureRate
expr: rate(gitops_webhook_requests_total{status="failure"}[5m]) > 0.1
for: 5m
severity: critical

# Kafka consumer lag
alert: HighKafkaLag
expr: port_agent_kafka_consumer_lag > 100
for: 10m
severity: warning
```

**Warning Alerts** (Slack):
```yaml
# Slow Git commits
alert: SlowGitCommits
expr: gitops_webhook_request_duration_seconds{handler=~"provision_.*"} > 10
for: 5m
severity: warning

# Port Ocean sync errors
alert: PortOceanSyncErrors
expr: rate(port_ocean_sync_errors_total[10m]) > 0.1
for: 10m
severity: warning
```

### Backup & Disaster Recovery

**Git Repository**:
- Primary source of truth - no additional backup needed
- GitHub provides automatic backups
- Enable branch protection on `main`

**Port Catalog**:
- Port.io handles SaaS backups
- Port Ocean Exporter continuously re-syncs from Kubernetes
- Infrastructure recreated from Git on cluster rebuild

**Recovery Procedures**:

**Scenario 1: Port Agent Pod Failure**
```bash
# Agent automatically restarts (Kubernetes deployment)
# No data loss - Kafka retains messages
kubectl rollout restart deployment/port-agent -n port-system
```

**Scenario 2: GitOps Webhook Service Failure**
```bash
# Restart service
kubectl rollout restart deployment/gitops-webhook -n port-gitops

# Replay failed actions from Port UI if needed
# Port tracks action run status
```

**Scenario 3: Complete Cluster Failure**
```bash
# 1. Rebuild cluster via Terraform
terraform apply

# 2. ArgoCD auto-syncs from Git
kubectl apply -f environments/dev/argocd/root-apps.yaml

# 3. Redeploy Port components
helm install port-agent port-labs/port-agent --namespace port-system -f port-agent-values.yaml
helm install k8s-exporter port-labs/port-ocean --namespace port-system -f ocean-exporter-config.yaml
kubectl apply -f k8s/  # GitOps webhook service

# 4. Port Ocean re-syncs catalog from Kubernetes
# All infrastructure state preserved in Git
```

---

## Security Considerations

### Network Security

**No Public Exposure Required**:
- Port Execution Agent uses **pull model** via Kafka (no inbound internet)
- GitOps Webhook Service is **ClusterIP only** (no LoadBalancer/Ingress)
- All communication internal to cluster or via HTTPS to SaaS

**Network Policies**:
```yaml
# Allow Port Agent to reach GitOps Webhook
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-agent-to-webhook
  namespace: port-gitops
spec:
  podSelector:
    matchLabels:
      app: gitops-webhook
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: port-system
      podSelector:
        matchLabels:
          app: port-agent
    ports:
    - protocol: TCP
      port: 8080

# Allow GitOps Webhook egress to GitHub API
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-webhook-to-github
  namespace: port-gitops
spec:
  podSelector:
    matchLabels:
      app: gitops-webhook
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
  - to:
    - podSelector: {}
    ports:
    - protocol: TCP
      port: 443
```

### Secrets Management

**GitHub PAT**:
- Store as Kubernetes Secret
- Use fine-grained PAT with **repo write only**
- Rotate every 90 days
- Never log or expose in error messages

**Port API Credentials**:
- Store as Kubernetes Secret
- Separate secrets for Agent vs Webhook service
- Use least-privilege (Agent: execute actions, Webhook: report status)

**Kafka Credentials**:
- Store as Kubernetes Secret
- SCRAM-SHA-512 authentication
- TLS encryption in transit

**Secret Rotation Procedure**:
```bash
# 1. Generate new GitHub PAT
NEW_PAT="ghp_new_token_here"

# 2. Update secret
kubectl create secret generic gitops-webhook-secrets \
  --namespace port-gitops \
  --from-literal=github-token="${NEW_PAT}" \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart pods to pick up new secret
kubectl rollout restart deployment/gitops-webhook -n port-gitops

# 4. Verify functionality
kubectl logs -n port-gitops -l app=gitops-webhook --tail=10
```

### RBAC

**Port Execution Agent**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: port-agent
  namespace: port-system
---
# No special Kubernetes RBAC needed - agent only forwards to webhooks
```

**Port Ocean Exporter**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: port-ocean-exporter
  namespace: port-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: port-ocean-exporter
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]  # Read-only
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: port-ocean-exporter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: port-ocean-exporter
subjects:
- kind: ServiceAccount
  name: port-ocean-exporter
  namespace: port-system
```

**GitOps Webhook Service**:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitops-webhook
  namespace: port-gitops
---
# No Kubernetes RBAC needed - service only calls GitHub API and Port API
# For Day-2 operations (kubectl commands), add role:
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: gitops-webhook-operations
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "patch"]  # For rollout restart
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "delete"]  # For pod operations
```

### Audit Logging

**Git Audit Trail**:
- Every infrastructure change recorded in Git history
- Commit messages include: user, Port run ID, action type
- Use `git log` to audit infrastructure changes

**Port Audit Logs**:
- Port maintains audit log of all actions
- Accessible via Port UI: Settings → Audit Logs
- Export via Port API for external SIEM

**Kubernetes Audit Logs**:
- Enable EKS audit logging to CloudWatch
- Track all `kubectl` operations by GitOps webhook service

**Example Audit Query** (Git):
```bash
# Show all Port-triggered changes in last 7 days
git log --since="7 days ago" --grep="\[Port\]" --pretty=format:"%h %ad | %s" --date=short

# Show changes by specific user
git log --grep="Triggered by: alice@company.com" --pretty=format:"%h %ad | %s" --date=short

# Show all S3 bucket creations
git log --all -- "environments/*/infrastructure/storage/*.yaml" --pretty=format:"%h %ad | %s" --date=short
```

---

## Troubleshooting

### Common Issues

#### Issue 1: Port Agent Not Receiving Events

**Symptoms**:
- Actions triggered in Port UI show "IN_PROGRESS" indefinitely
- Agent logs show: `No messages consumed`

**Debug Steps**:
```bash
# Check agent pod status
kubectl get pods -n port-system -l app=port-agent

# Check agent logs
kubectl logs -n port-system -l app=port-agent --tail=100

# Check Kafka connectivity
kubectl exec -it -n port-system deployment/port-agent -- \
  sh -c 'nc -zv <KAFKA_ENDPOINT> 9092'

# Verify Kafka credentials
kubectl get secret port-agent-secrets -n port-system -o yaml
```

**Common Causes**:
- Incorrect Kafka endpoint or topic name
- Invalid Kafka credentials
- Network policy blocking egress to Kafka
- Agent not subscribed to correct consumer group

**Resolution**:
```bash
# Update Kafka configuration
helm upgrade port-agent port-labs/port-agent \
  --namespace port-system \
  --reuse-values \
  --set kafka.bootstrapServers="<CORRECT_ENDPOINT>" \
  --set kafka.topic="<CORRECT_TOPIC>"

# Restart agent
kubectl rollout restart deployment/port-agent -n port-system
```

#### Issue 2: GitOps Webhook Service Failing

**Symptoms**:
- Agent logs show: `Webhook call failed: Connection refused`
- Port action status shows "FAILURE"

**Debug Steps**:
```bash
# Check webhook service status
kubectl get pods -n port-gitops -l app=gitops-webhook

# Check service endpoints
kubectl get svc gitops-webhook -n port-gitops
kubectl get endpoints gitops-webhook -n port-gitops

# Test webhook connectivity from agent namespace
kubectl run -it --rm debug --image=curlimages/curl --restart=Never --namespace=port-system -- \
  curl -v http://gitops-webhook.port-gitops.svc.cluster.local:8080/health

# Check webhook logs
kubectl logs -n port-gitops -l app=gitops-webhook --tail=100
```

**Common Causes**:
- Webhook service not running
- Service DNS name incorrect in agent configuration
- Network policy blocking traffic
- Webhook service crashed due to invalid GitHub token

**Resolution**:
```bash
# Restart webhook service
kubectl rollout restart deployment/gitops-webhook -n port-gitops

# Update agent webhook URL if needed
helm upgrade port-agent port-labs/port-agent \
  --namespace port-system \
  --reuse-values \
  --set webhook.url="http://gitops-webhook.port-gitops.svc.cluster.local:8080"
```

#### Issue 3: Git Commit Failures

**Symptoms**:
- Webhook logs show: `Failed to commit to Git: 401 Unauthorized`
- Port action status shows "FAILURE" with message about Git

**Debug Steps**:
```bash
# Check GitHub token validity
kubectl get secret gitops-webhook-secrets -n port-gitops -o jsonpath='{.data.github-token}' | base64 -d | \
  xargs -I {} curl -H "Authorization: token {}" https://api.github.com/user

# Check webhook logs for detailed error
kubectl logs -n port-gitops -l app=gitops-webhook --tail=50 | grep -i "git"

# Verify repository access
kubectl exec -it -n port-gitops deployment/gitops-webhook -- \
  python -c "from github import Github; g = Github('TOKEN'); print(g.get_repo('your-org/portal-kombat').name)"
```

**Common Causes**:
- GitHub PAT expired or invalid
- PAT missing `repo` scope
- Repository name incorrect in configuration
- Branch protection preventing automated commits

**Resolution**:
```bash
# Generate new GitHub PAT with correct scopes
# Update secret
kubectl create secret generic gitops-webhook-secrets \
  --namespace port-gitops \
  --from-literal=github-token="${NEW_GITHUB_PAT}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart webhook service
kubectl rollout restart deployment/gitops-webhook -n port-gitops
```

#### Issue 4: ArgoCD Not Syncing

**Symptoms**:
- Git commit successful
- ArgoCD application shows "OutOfSync" but not syncing
- Crossplane resource not created

**Debug Steps**:
```bash
# Check ArgoCD application status
kubectl get applications -n argocd

# Describe specific application
kubectl describe application dev-infrastructure-claims -n argocd

# Check ArgoCD sync policy
kubectl get application dev-infrastructure-claims -n argocd -o jsonpath='{.spec.syncPolicy}'

# Trigger manual sync
kubectl patch application dev-infrastructure-claims -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

**Common Causes**:
- ArgoCD auto-sync disabled
- Sync wave dependencies preventing sync
- Invalid manifest (YAML syntax error)
- ArgoCD application not watching correct Git path

**Resolution**:
```bash
# Enable auto-sync
kubectl patch application dev-infrastructure-claims -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'

# Validate manifest locally
kubectl apply --dry-run=client -f environments/dev/infrastructure/storage/my-bucket.yaml
```

#### Issue 5: Crossplane Not Provisioning

**Symptoms**:
- ArgoCD synced successfully
- Crossplane claim created but stuck in "Provisioning"
- No AWS resource created

**Debug Steps**:
```bash
# Check claim status
kubectl get objectstorage -A
kubectl describe objectstorage my-bucket-claim

# Check Crossplane managed resources
kubectl get managed

# Check Crossplane provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3

# Check provider health
kubectl get providers
```

**Common Causes**:
- Crossplane provider not healthy
- AWS credentials invalid (IRSA misconfigured)
- Composition missing or invalid
- AWS API rate limiting

**Resolution**:
```bash
# Check provider config
kubectl get providerconfig default -o yaml

# Restart Crossplane provider
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3

# Check AWS credentials
kubectl describe sa -n crossplane-system | grep eks.amazonaws.com/role-arn
```

### Debug Checklist

When troubleshooting action execution:

1. ✅ **Port UI**: Action triggered and run created?
2. ✅ **Port Agent**: Consuming Kafka events? Check logs
3. ✅ **GitOps Webhook**: Receiving webhook? Check logs
4. ✅ **GitHub**: Commit successful? Check commit history
5. ✅ **ArgoCD**: Syncing? Check application status
6. ✅ **Crossplane**: Provisioning? Check claim status
7. ✅ **AWS**: Resource created? Check AWS console
8. ✅ **Port Catalog**: Entity synced? Check Port UI

### Support Resources

**Port.io Support**:
- Email: support@getport.io
- Slack Community: [Port Slack](https://www.getport.io/community)
- Documentation: https://docs.port.io

**Portal Kombat Internal**:
- Platform Team Slack: `#platform-engineering`
- On-call: PagerDuty rotation
- Runbook: `docs/runbooks/port-control-plane.md`

---

## Appendix

### Glossary

**Port.io Terms**:
- **Blueprint**: Schema definition for a type of resource (like a database table schema)
- **Entity**: Instance of a blueprint (like a database row)
- **Action**: Self-service operation (CREATE, DAY-2, DELETE)
- **Action Run**: Execution instance of an action
- **Ocean Integration**: Port's framework for syncing external data into catalog
- **Execution Agent**: Self-hosted Kafka consumer for action execution

**Portal Kombat Terms**:
- **Crossplane Claim**: User-facing request for infrastructure (uses XRD)
- **Composition**: Implementation of how Crossplane provisions resources
- **XRD**: CompositeResourceDefinition - defines custom infrastructure API
- **App-of-Apps**: ArgoCD pattern for hierarchical application management

### References

**Port.io Documentation**:
- Port Execution Agent: https://docs.port.io/actions-and-automations/setup-backend/webhook/port-execution-agent/
- Port Ocean Exporter: https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/kubernetes/
- Custom CRDs: https://docs.port.io/build-your-software-catalog/sync-data-to-catalog/kubernetes-stack/kubernetes/port-crd

**Portal Kombat Documentation**:
- Architecture: `docs/ARCHITECTURE.md`
- Quick Start: `docs/QUICK-START.md`
- Naming Conventions: `docs/NAMING_CONVENTIONS.md`
- Claude Integration: `CLAUDE.md`

**Crossplane**:
- Documentation: https://docs.crossplane.io/
- AWS Provider: https://marketplace.upbound.io/providers/upbound/provider-aws/

**ArgoCD**:
- Documentation: https://argo-cd.readthedocs.io/
- Best Practices: https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/

---

**Document Version**: 1.0
**Last Updated**: 2025-11-05
**Status**: Design Complete, Ready for Implementation
**Next Steps**: Phase 1 deployment (Port setup and component installation)
