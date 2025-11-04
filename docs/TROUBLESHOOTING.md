# Portal Kombat Kubernetes Cluster Troubleshooting Guide

**Last Updated**: 2025-11-03
**Cluster**: raiden-control-plane (EKS v1.33.5)
**Location**: us-east-2

---

## Executive Summary

### Current Cluster Status: ⚠️ ATTENTION REQUIRED

**Critical Findings**:
1. 🔴 **ArgoCD Application Out of Sync**: `dev-infrastructure` application requires synchronization
2. 🟡 **Missing Crossplane Providers**: No provider resources detected in cluster
3. 🟡 **No Monitoring Namespace Workloads**: kube-prometheus-stack deployed but no pods running
4. 🟢 **Core Infrastructure Healthy**: All critical system pods running normally
5. 🟢 **High Availability**: 3-node cluster across 3 availability zones (SPOT instances)

**Risk Assessment**:
- **Infrastructure Drift Risk**: HIGH - ArgoCD out of sync may cause config drift
- **Crossplane Availability**: MEDIUM - Providers deployed but need validation
- **Node Disruption Risk**: MEDIUM - SPOT instances without termination handler
- **Monitoring Gap**: MEDIUM - Prometheus stack not actively monitoring

---

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Critical Issues](#critical-issues)
3. [System Architecture](#system-architecture)
4. [Common Issues](#common-issues)
5. [Diagnostic Commands](#diagnostic-commands)
6. [Component Troubleshooting](#component-troubleshooting)
7. [Recovery Procedures](#recovery-procedures)
8. [Preventive Measures](#preventive-measures)

---

## Quick Reference

### Emergency Contacts
- **Slack**: #portal-kombat-incidents
- **On-Call**: ArgoCD/Crossplane team rotation
- **Escalation**: Platform team lead

### Critical Health Check Commands
```bash
# Overall cluster health (run first)
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# ArgoCD application status
kubectl get applications -n argocd

# Crossplane provider health
kubectl get providers
kubectl get providerconfigs

# Resource consumption
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory | head -20
```

### Quick Fix Commands
```bash
# Sync out-of-sync ArgoCD application
kubectl patch application dev-infrastructure -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Restart stuck Crossplane provider
kubectl rollout restart deployment -n crossplane-system [provider-name]

# Clear completed pods
kubectl delete pods --field-selector=status.phase==Succeeded --all-namespaces

# Force pod rescheduling
kubectl delete pod [pod-name] -n [namespace]
```

---

## Critical Issues

### 🔴 ISSUE #1: ArgoCD Infrastructure Application Out of Sync

**Status**: OutOfSync but Healthy
**Impact**: Configuration drift, infrastructure changes not applied
**Affected Component**: `dev-infrastructure` application
**Git Revision**: `612df4e0b6e3a20fae2ef509668a3d8709ee19f4`

#### Symptoms
- ArgoCD shows "OutOfSync" status for dev-infrastructure
- Git changes not automatically applied to cluster
- Manual sync required for infrastructure updates

#### Root Cause
ArgoCD auto-sync may be disabled or sync failed due to:
- Validation errors in manifests
- Resource conflicts or CRD issues
- Prune failures on deleted resources
- Sync waves not completing

#### Diagnostic Steps
```bash
# 1. Check application details
kubectl describe application dev-infrastructure -n argocd

# 2. View sync status and diff
kubectl get application dev-infrastructure -n argocd -o yaml | grep -A 20 status

# 3. Check ArgoCD controller logs
kubectl logs -n argocd argo-cd-argocd-application-controller-0 --tail=100 | grep dev-infrastructure

# 4. View application events
kubectl get events -n argocd --field-selector involvedObject.name=dev-infrastructure
```

#### Resolution

**Option 1: Force Sync (Immediate)**
```bash
# Sync with prune and replace
kubectl patch application dev-infrastructure -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{},"syncOptions":["CreateNamespace=true","PruneLast=true","Replace=true"]}}}}'

# Monitor sync progress
kubectl get application dev-infrastructure -n argocd -w
```

**Option 2: Manual Sync via ArgoCD UI**
```bash
# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port forward to ArgoCD UI
kubectl port-forward svc/argo-cd-argocd-server -n argocd 8080:443

# Navigate to: https://localhost:8080
# Username: admin
# Click: dev-infrastructure → SYNC → SYNCHRONIZE
```

**Option 3: Enable Auto-Sync**
```bash
# Edit application to enable auto-sync
kubectl patch application dev-infrastructure -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

#### Verification
```bash
# Check application is synced
kubectl get application dev-infrastructure -n argocd -o jsonpath='{.status.sync.status}' && echo

# Should show: Synced

# Verify resources deployed
kubectl get all -n [infrastructure-namespace]
```

#### Prevention
- Enable automated sync with prune and self-heal
- Set up ArgoCD notifications for sync failures
- Use sync waves to control deployment order
- Implement pre-sync hooks for validation

---

### 🟡 ISSUE #2: Missing Crossplane Provider Resources

**Status**: Providers deployed but no CRDs detected
**Impact**: Infrastructure provisioning unavailable
**Affected Component**: All Crossplane AWS providers

#### Symptoms
- `kubectl get providers` returns no resources
- Crossplane provider pods running but CRDs not registered
- Cannot create Crossplane managed resources
- ProviderConfigs may not be recognized

#### Root Cause Analysis
1. **CRD Installation Delay**: Providers take 2-5 minutes to install CRDs
2. **RBAC Issues**: Service account lacks permissions to create CRDs
3. **Provider Health**: Providers unhealthy, not installing resources
4. **Package Installation**: Provider packages not fully extracted

#### Diagnostic Steps
```bash
# 1. Check if Provider CRD exists
kubectl get crd providers.pkg.crossplane.io

# 2. Check Crossplane core installation
kubectl get pods -n crossplane-system -l app=crossplane

# 3. Check provider packages
kubectl get packages -A

# 4. Check provider revision health
kubectl get providerrevision

# 5. Check provider pod logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=upbound-provider-family-aws --tail=50

# 6. Check for CRD installation
kubectl get crd | grep aws | wc -l
# Should show 200+ CRDs for AWS providers
```

#### Resolution

**Step 1: Verify Crossplane Installation**
```bash
# Check Crossplane core is healthy
kubectl get deployment crossplane -n crossplane-system
kubectl logs deployment/crossplane -n crossplane-system --tail=100

# If unhealthy, restart
kubectl rollout restart deployment/crossplane -n crossplane-system
```

**Step 2: Check Provider Package Installation**
```bash
# List all provider packages
kubectl get providers,providerrevisions

# If empty, providers not installed - check ArgoCD sync
kubectl get application dev-platform-crossplane -n argocd
```

**Step 3: Wait for CRD Installation**
```bash
# Provider CRDs take time to install - wait and watch
kubectl get crd | grep -E "aws|crossplane" -c

# Watch provider revision status
kubectl get providerrevision -w
```

**Step 4: Check Provider RBAC**
```bash
# Verify service accounts exist
kubectl get sa -n crossplane-system | grep provider

# Check for IRSA annotations (AWS IAM roles)
kubectl get sa -n crossplane-system -o yaml | grep eks.amazonaws.com/role-arn
```

**Step 5: Manual Provider Reinstall (if needed)**
```bash
# Get current provider configuration
kubectl get provider -n crossplane-system -o yaml > providers-backup.yaml

# Delete and recreate specific provider
kubectl delete provider provider-aws-s3
kubectl apply -f providers-backup.yaml

# Wait for installation
kubectl wait --for=condition=healthy provider/provider-aws-s3 --timeout=300s
```

#### Verification
```bash
# 1. Verify provider CRDs installed
kubectl get crd | grep -E "s3.aws|ec2.aws|eks.aws" | head -10

# 2. Verify providers healthy
kubectl get providers

# 3. Verify provider configs
kubectl get providerconfigs

# 4. Test resource creation
cat <<EOF | kubectl apply -f -
apiVersion: s3.aws.upbound.io/v1beta1
kind: Bucket
metadata:
  name: test-bucket-verification
spec:
  forProvider:
    region: us-east-2
  providerConfigRef:
    name: default
EOF

# Check bucket status
kubectl describe bucket test-bucket-verification

# Cleanup test
kubectl delete bucket test-bucket-verification
```

#### Prevention
- Monitor provider installation progress during bootstrap
- Set up alerting for provider health status
- Document provider installation timelines
- Use provider readiness probes

---

### 🟡 ISSUE #3: Prometheus Monitoring Stack Not Running

**Status**: Helm chart deployed, no pods in monitoring namespace
**Impact**: No cluster metrics, alerting, or observability
**Affected Component**: kube-prometheus-stack

#### Symptoms
- Helm release shows "deployed" status
- No pods running in kube-prometheus-stack namespace
- Grafana, Prometheus, AlertManager unavailable
- No metrics collection occurring

#### Root Cause
Common causes:
1. Namespace mismatch (chart in kube-prometheus-stack, expected in monitoring)
2. Resource constraints preventing pod scheduling
3. PersistentVolume claims not satisfied
4. Init container failures
5. Image pull errors

#### Diagnostic Steps
```bash
# 1. Check helm release
helm list -n kube-prometheus-stack

# 2. Check for pods
kubectl get pods -n kube-prometheus-stack
kubectl get pods -n monitoring

# 3. Check for pending resources
kubectl get all -n kube-prometheus-stack
kubectl get pvc -n kube-prometheus-stack

# 4. Check for events
kubectl get events -n kube-prometheus-stack --sort-by='.lastTimestamp' | tail -20

# 5. Check Prometheus Operator CRDs
kubectl get crd | grep monitoring.coreos.com

# 6. Check for ServiceMonitors
kubectl get servicemonitor -A
```

#### Resolution

**Step 1: Verify Helm Release Configuration**
```bash
# Get helm values
helm get values kube-prometheus-stack -n kube-prometheus-stack

# Check release history
helm history kube-prometheus-stack -n kube-prometheus-stack
```

**Step 2: Check Resource Deployment**
```bash
# List all resources created by helm
kubectl get all,pvc,cm,secret -n kube-prometheus-stack -l release=kube-prometheus-stack

# Check for deployments/statefulsets
kubectl get deployments,statefulsets -n kube-prometheus-stack
```

**Step 3: Fix Namespace Issue (if applicable)**
```bash
# If resources expected in 'monitoring' namespace
# Option A: Reinstall with correct namespace
helm uninstall kube-prometheus-stack -n kube-prometheus-stack
kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi

# Option B: Move resources (complex, not recommended)
```

**Step 4: Check Resource Constraints**
```bash
# Check node resources
kubectl top nodes

# Check if scheduling constrained
kubectl get events -A | grep -i "insufficient\|failed.*schedule"

# Verify PVCs can bind
kubectl get pvc -A | grep Pending
```

**Step 5: Restart Prometheus Operator**
```bash
# If CRDs installed but no controllers
kubectl rollout restart deployment -n kube-prometheus-stack -l app.kubernetes.io/name=kube-prometheus-stack
```

#### Verification
```bash
# 1. Check all pods running
kubectl get pods -n monitoring
# OR
kubectl get pods -n kube-prometheus-stack

# Should see:
# - prometheus-operator
# - prometheus-server
# - alertmanager
# - grafana
# - node-exporter (daemonset)
# - kube-state-metrics

# 2. Verify Prometheus accessible
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# 3. Verify Grafana accessible
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# 4. Check metrics collection
kubectl get servicemonitor -A
```

#### Prevention
- Use consistent namespace naming
- Pre-provision PVs if using static provisioning
- Set resource requests/limits appropriately
- Test monitoring stack in non-production first

---

### 🟡 ISSUE #4: SPOT Instance Disruption Risk

**Status**: Preventive measure needed
**Impact**: Potential pod evictions without graceful shutdown
**Affected Component**: All nodes (SPOT instances)

#### Background
All cluster nodes are SPOT instances (`eks.amazonaws.com/capacityType=SPOT`), which can be terminated with 2-minute notice by AWS. Without proper handling, this can cause:
- Abrupt pod terminations
- Data loss for stateful workloads
- Service disruptions
- Failed drains

#### Risk Level: **MEDIUM**
- Cluster has multiple nodes across AZs (good)
- No node termination handler detected (concern)
- Critical infrastructure may not gracefully drain

#### Recommended Solution: Install AWS Node Termination Handler

**Step 1: Install via Helm**
```bash
# Add EKS charts repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install node termination handler
helm install aws-node-termination-handler eks/aws-node-termination-handler \
  --namespace kube-system \
  --set enableSpotInterruptionDraining=true \
  --set enableRebalanceMonitoring=true \
  --set enableScheduledEventDraining=true \
  --set logLevel=info

# Verify installation
kubectl get daemonset aws-node-termination-handler -n kube-system
```

**Step 2: Configure ArgoCD Management**
```bash
# Create ArgoCD application for node termination handler
cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: aws-node-termination-handler
  namespace: argocd
spec:
  destination:
    namespace: kube-system
    server: https://kubernetes.default.svc
  project: default
  source:
    chart: aws-node-termination-handler
    repoURL: https://aws.github.io/eks-charts
    targetRevision: 0.21.0
    helm:
      values: |
        enableSpotInterruptionDraining: true
        enableRebalanceMonitoring: true
        enableScheduledEventDraining: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

**Step 3: Verify Operation**
```bash
# Check handler pods running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler

# Check logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler --tail=50

# Simulate spot interruption (testing)
# (Only in non-production)
kubectl create configmap spot-interruption-test -n kube-system \
  --from-literal=action-type=spot-itn
```

#### Alternative: Use SQS Queue Method
For better reliability, use SQS-based interruption handling:

```bash
# Create SQS queue for interruption events (Terraform)
# See: bootstrap/eks-bootstrap/node-termination-handler.tf

# Install with SQS configuration
helm install aws-node-termination-handler eks/aws-node-termination-handler \
  --namespace kube-system \
  --set enableSqsTerminationDraining=true \
  --set queueURL=https://sqs.us-east-2.amazonaws.com/ACCOUNT_ID/spot-interruptions \
  --set awsRegion=us-east-2
```

#### Verification
```bash
# Ensure handler is running on all nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-node-termination-handler -o wide

# Check node labels for handler
kubectl get nodes -L aws-node-termination-handler/instance-id

# Monitor for interruption events
kubectl get events -A | grep -i "spot\|termination\|drain"
```

---

## System Architecture

### Cluster Overview
- **Platform**: Amazon EKS v1.33.5
- **Region**: us-east-2 (Ohio)
- **Nodes**: 3 x m5.xlarge SPOT instances
- **Availability Zones**: us-east-2a, us-east-2b, us-east-2c
- **Networking**: AWS VPC CNI (10.140.0.0/16)
- **Container Runtime**: containerd 2.1.4
- **Kubernetes API**: `https://31F74548D0C0D4910526F1FBE62C72B5.gr7.us-east-2.eks.amazonaws.com`

### Component Layout

```
┌─────────────────────────────────────────────────────────────┐
│                    EKS Control Plane (Managed)              │
└─────────────────────────────────────────────────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
┌───────▼────────┐   ┌──────────────┐   ┌────▼─────────┐
│  Node AZ-2a    │   │  Node AZ-2b  │   │  Node AZ-2c  │
│  m5.xlarge     │   │  m5.xlarge   │   │  m5.xlarge   │
│  SPOT          │   │  SPOT        │   │  SPOT        │
└───────┬────────┘   └──────┬───────┘   └────┬─────────┘
        │                   │                 │
        └───────────────────┴─────────────────┘
                           │
        ┌──────────────────┴──────────────────┐
        │                                     │
┌───────▼────────────────┐    ┌──────────────▼──────┐
│  System Namespaces     │    │  App Namespaces     │
│  - kube-system         │    │  - argocd           │
│  - crossplane-system   │    │  - nodejs           │
│  - gatekeeper-system   │    │  - monitoring       │
│  - kube-prometheus-*   │    │                     │
└────────────────────────┘    └─────────────────────┘
```

### Resource Distribution

| Namespace           | Pods | Memory Usage | CPU Usage |
|--------------------|------|--------------|-----------|
| crossplane-system  | 26   | ~2.4 GiB     | ~40m      |
| argocd             | 6    | ~586 MiB     | ~10m      |
| kube-system        | 23   | ~321 MiB     | ~35m      |
| gatekeeper-system  | 4    | ~352 MiB     | ~12m      |
| **Total**          | 59   | **3.5 GiB**  | **97m**   |

**Node Capacity**: 3 nodes × 4 vCPU × 16 GiB = 12 vCPU, 48 GiB
**Current Usage**: 97m CPU (0.8%), 3.5 GiB memory (7.3%)
**Status**: ✅ Well under capacity

---

## Common Issues

### ArgoCD Issues

#### Application Stuck in Progressing State
**Symptoms**: Application shows "Progressing" for extended period

**Diagnosis**:
```bash
kubectl describe application [app-name] -n argocd
kubectl get events -n argocd --field-selector involvedObject.name=[app-name]
```

**Common Causes**:
- Health check misconfiguration
- Resource creation timeout
- Sync waves not progressing
- Webhook validation blocking

**Resolution**:
```bash
# Skip health check temporarily
kubectl patch application [app-name] -n argocd \
  --type merge -p '{"spec":{"ignoreDifferences":[{"group":"*","kind":"*"}]}}'

# Force sync with timeout
kubectl patch application [app-name] -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncOptions":["Timeout=5m"]}}}'
```

#### Cannot Access ArgoCD UI
**Symptoms**: Connection refused or timeout on port-forward

**Diagnosis**:
```bash
kubectl get svc -n argocd
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50
```

**Resolution**:
```bash
# Restart ArgoCD server
kubectl rollout restart deployment argo-cd-argocd-server -n argocd

# Check service endpoints
kubectl get endpoints -n argocd argo-cd-argocd-server

# Alternative: Use NodePort temporarily
kubectl patch svc argo-cd-argocd-server -n argocd \
  --type merge -p '{"spec":{"type":"NodePort"}}'
```

---

### Crossplane Issues

#### Provider Not Becoming Healthy
**Symptoms**: Provider stuck in "Installing" or "Unknown" state

**Diagnosis**:
```bash
kubectl describe provider [provider-name]
kubectl get providerrevision | grep [provider-name]
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=[provider-name] --tail=100
```

**Common Causes**:
- CRD installation timeout
- Image pull failure
- RBAC permissions missing
- Provider package corrupted

**Resolution**:
```bash
# Check provider revision
kubectl get providerrevision -l pkg.crossplane.io/provider=[provider-name]

# Delete and recreate provider
kubectl delete provider [provider-name]
kubectl apply -f platform/providers/[provider-name].yaml

# Monitor installation
kubectl get provider [provider-name] -w
```

#### Managed Resources Stuck in "Creating"
**Symptoms**: Crossplane resources not creating AWS infrastructure

**Diagnosis**:
```bash
kubectl describe [resource-type] [resource-name]
kubectl get events | grep [resource-name]
```

**Common Causes**:
- ProviderConfig not set or incorrect
- AWS IAM permissions missing
- Resource already exists in AWS
- Invalid resource specification
- AWS API throttling

**Resolution**:
```bash
# Check provider config
kubectl get providerconfig default -o yaml

# Verify IAM role annotations
kubectl get sa -n crossplane-system -o yaml | grep eks.amazonaws.com/role-arn

# Check AWS credentials (if using secrets)
kubectl get secret -n crossplane-system aws-creds -o yaml

# View detailed error
kubectl describe [resource-type] [resource-name] | grep -A 10 "Message:"

# Delete and recreate resource
kubectl delete [resource-type] [resource-name]
kubectl apply -f [resource-file].yaml
```

---

### Node and Scheduling Issues

#### Pods Stuck in Pending State
**Symptoms**: Pods not scheduling to nodes

**Diagnosis**:
```bash
kubectl describe pod [pod-name] -n [namespace] | grep -A 10 Events
kubectl get events -A | grep -i "insufficient\|failed.*schedule"
kubectl top nodes
```

**Common Causes**:
- Insufficient resources (CPU/memory)
- Node affinity/anti-affinity not satisfied
- Taints on nodes
- PersistentVolumeClaim not bound
- Resource quotas exceeded

**Resolution**:
```bash
# Check node capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check for taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Remove taint if blocking
kubectl taint nodes [node-name] [taint-key]-

# Scale node group (if needed)
# Update EKS node group desired capacity in AWS Console or Terraform
```

#### Node Not Ready
**Symptoms**: Node shows NotReady status

**Diagnosis**:
```bash
kubectl describe node [node-name]
kubectl get events | grep [node-name]
```

**Common Causes**:
- kubelet not running
- Network plugin issues
- Disk pressure
- Memory pressure
- PID pressure

**Resolution**:
```bash
# Check node conditions
kubectl get node [node-name] -o jsonpath='{.status.conditions}' | jq

# Cordon node to prevent new pods
kubectl cordon [node-name]

# Drain node safely
kubectl drain [node-name] --ignore-daemonsets --delete-emptydir-data

# If node unrecoverable, terminate instance
# Node will be replaced by Auto Scaling Group
```

---

## Diagnostic Commands

### Cluster-Wide Diagnostics

```bash
# Complete cluster overview
kubectl get all --all-namespaces

# Node health and capacity
kubectl get nodes -o wide
kubectl describe nodes | grep -E "Name:|Roles:|Conditions:|Allocated resources:" -A 3

# Resource consumption
kubectl top nodes
kubectl top pods --all-namespaces --sort-by=memory | head -20

# Identify problems
kubectl get pods --all-namespaces --field-selector=status.phase!=Running
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50

# Check for evicted/failed pods
kubectl get pods --all-namespaces | grep -E "Evicted|OOMKilled|Error|CrashLoop"

# Network connectivity
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash
# Inside pod:
# nslookup kubernetes.default
# curl -k https://kubernetes.default.svc.cluster.local
```

### Component-Specific Diagnostics

#### ArgoCD
```bash
# Application status
kubectl get applications -n argocd
kubectl describe application [app-name] -n argocd

# Sync operation details
kubectl get application [app-name] -n argocd -o jsonpath='{.status.operationState}' | jq

# ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=100
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=100
```

#### Crossplane
```bash
# Provider health
kubectl get providers
kubectl get providerrevisions

# Provider configurations
kubectl get providerconfigs

# Managed resources
kubectl get managed
kubectl get composite

# Crossplane logs
kubectl logs -n crossplane-system -l app=crossplane --tail=100
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=upbound-provider-family-aws --tail=100

# Check specific provider
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-upjet-aws-s3 --tail=100
```

#### EKS Add-ons
```bash
# AWS Load Balancer Controller
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=50

# EBS CSI Driver
kubectl logs -n kube-system -l app=ebs-csi-controller --tail=50
kubectl get csidriver
kubectl get csistoragecapacity --all-namespaces

# CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
kubectl get cm -n kube-system coredns -o yaml

# VPC CNI
kubectl logs -n kube-system -l k8s-app=aws-node --tail=50
kubectl get daemonset -n kube-system aws-node
```

---

## Component Troubleshooting

### ArgoCD Deep Dive

#### Application Sync Failures

**Issue**: Application fails to sync with validation errors

**Investigation**:
```bash
# Get detailed sync results
kubectl get application [app-name] -n argocd -o yaml | grep -A 50 operationState

# Check for resource validation errors
kubectl describe application [app-name] -n argocd | grep -A 20 "Sync Failed"

# View manifests ArgoCD is trying to apply
kubectl get application [app-name] -n argocd -o jsonpath='{.status.resources}' | jq
```

**Resolution**:
```bash
# Bypass validation temporarily
kubectl patch application [app-name] -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"syncOptions":["Validate=false"]}}}'

# Apply with server-side dry run
kubectl patch application [app-name] -n argocd \
  --type merge -p '{"spec":{"syncPolicy":{"syncOptions":["ServerSideApply=true"]}}}'

# Skip specific resources
kubectl patch application [app-name] -n argocd \
  --type merge -p '{"spec":{"ignoreDifferences":[{"group":"apps","kind":"Deployment","jsonPointers":["/spec/replicas"]}]}}'
```

#### Repository Connection Issues

**Issue**: ArgoCD cannot connect to Git repository

**Investigation**:
```bash
# Check repo connection
kubectl get application [app-name] -n argocd -o jsonpath='{.status.sourceType}' && echo

# Test repository access
kubectl exec -n argocd argo-cd-argocd-repo-server-[pod-suffix] -- \
  git ls-remote [repo-url]

# Check credentials
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository
```

**Resolution**:
```bash
# Update repository credentials
kubectl create secret generic repo-credentials -n argocd \
  --from-literal=username=[username] \
  --from-literal=password=[token] \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart repo server to refresh
kubectl rollout restart deployment argo-cd-argocd-repo-server -n argocd
```

---

### Crossplane Deep Dive

#### Provider Configuration Troubleshooting

**Issue**: ProviderConfig not working, managed resources can't authenticate

**Investigation**:
```bash
# Check ProviderConfig details
kubectl describe providerconfig default

# Verify referenced credentials
kubectl get secret -n crossplane-system [secret-name] -o yaml

# Check IRSA configuration
kubectl get sa -n crossplane-system -o yaml | grep -A 5 eks.amazonaws.com/role-arn

# Test AWS credentials from provider pod
kubectl exec -n crossplane-system [provider-pod] -- \
  env | grep AWS
```

**Resolution Using IRSA (Recommended)**:
```bash
# Ensure service account has correct annotation
kubectl annotate sa -n crossplane-system [provider-sa] \
  eks.amazonaws.com/role-arn=arn:aws:iam::[account-id]:role/crossplane-sa-role \
  --overwrite

# Restart provider to pick up annotation
kubectl rollout restart deployment -n crossplane-system [provider-deployment]

# Verify IRSA token mounted
kubectl exec -n crossplane-system [provider-pod] -- \
  ls -la /var/run/secrets/eks.amazonaws.com/serviceaccount/
```

**Resolution Using Secret**:
```bash
# Create AWS credentials secret
kubectl create secret generic aws-creds -n crossplane-system \
  --from-literal=credentials="[aws-credentials-file-content]"

# Update ProviderConfig to use secret
kubectl patch providerconfig default --type merge -p '
{
  "spec": {
    "credentials": {
      "source": "Secret",
      "secretRef": {
        "name": "aws-creds",
        "namespace": "crossplane-system",
        "key": "credentials"
      }
    }
  }
}'
```

#### Composition Debugging

**Issue**: Composite resource not creating expected managed resources

**Investigation**:
```bash
# Check composition exists
kubectl get composition

# View composite resource status
kubectl describe [xrd-kind] [resource-name]

# Check for composition errors
kubectl get events | grep [resource-name]

# View what resources should be created
kubectl get composition [composition-name] -o yaml | grep -A 50 resources
```

**Resolution**:
```bash
# Verify composition selector matches
kubectl get [xrd-kind] [resource-name] -o yaml | grep compositionRef

# Check patch-and-transform function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/function=function-patch-and-transform

# Delete and recreate composite resource
kubectl delete [xrd-kind] [resource-name]
kubectl apply -f [xrd-claim-file].yaml
```

---

### Networking Issues

#### DNS Resolution Failures

**Symptoms**: Pods cannot resolve internal service names

**Investigation**:
```bash
# Test DNS from a pod
kubectl run tmp-shell --rm -i --tty --image busybox -- /bin/sh
# Inside pod:
# nslookup kubernetes.default
# nslookup [service-name].[namespace].svc.cluster.local

# Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Check CoreDNS config
kubectl get cm -n kube-system coredns -o yaml
```

**Resolution**:
```bash
# Restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Check CoreDNS service
kubectl get svc -n kube-system kube-dns
kubectl describe svc -n kube-system kube-dns

# Verify DNS service IP in pod resolv.conf
kubectl exec [pod-name] -- cat /etc/resolv.conf
```

#### Service Connectivity Issues

**Symptoms**: Cannot reach services via ClusterIP

**Investigation**:
```bash
# Check service endpoints
kubectl get endpoints [service-name] -n [namespace]

# Verify pods are labeled correctly
kubectl get pods -n [namespace] --show-labels

# Test connectivity
kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot -- /bin/bash
# Inside pod:
# curl -v http://[service-name].[namespace].svc.cluster.local:[port]

# Check kube-proxy
kubectl get pods -n kube-system -l k8s-app=kube-proxy
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=50
```

**Resolution**:
```bash
# Restart kube-proxy
kubectl rollout restart daemonset kube-proxy -n kube-system

# Check iptables rules (from node)
# SSH to node and run:
# sudo iptables-save | grep [service-name]

# Verify service selector matches pods
kubectl get svc [service-name] -n [namespace] -o yaml | grep selector -A 5
kubectl get pods -n [namespace] -l [selector-key]=[selector-value]
```

---

## Recovery Procedures

### Complete Cluster Disaster Recovery

**Scenario**: Cluster completely unresponsive or needs rebuild

#### Prerequisites
- Access to AWS Console or CLI
- Git repository access
- ArgoCD bootstrap manifests
- Backup of critical secrets

#### Recovery Steps

**Step 1: Verify Cluster Status**
```bash
# Check cluster exists and is accessible
kubectl cluster-info
kubectl get nodes

# If no response, check AWS EKS console
aws eks describe-cluster --name raiden --region us-east-2
```

**Step 2: Restore Control Plane Access**
```bash
# Update kubeconfig
aws eks update-kubeconfig --name raiden --region us-east-2

# Verify connectivity
kubectl get nodes
```

**Step 3: Restore Core Add-ons**
```bash
# Install Crossplane
kubectl create namespace crossplane-system
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system \
  --version 2.0.2

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.1.9/manifests/install.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

**Step 4: Restore GitOps Applications**
```bash
# Apply root ArgoCD application
kubectl apply -f environments/dev/argocd/root-app.yaml

# Monitor restoration
kubectl get applications -n argocd -w
```

**Step 5: Verify Infrastructure Recovery**
```bash
# Check all applications synced
kubectl get applications -n argocd

# Check Crossplane providers
kubectl get providers

# Verify workloads
kubectl get pods --all-namespaces
```

**Step 6: Restore Monitoring and Observability**
```bash
# Sync monitoring stack
kubectl patch application kube-prometheus-stack -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Verify Prometheus and Grafana
kubectl get pods -n monitoring
```

---

### Crossplane Provider Recovery

**Scenario**: All Crossplane providers corrupted or not functioning

**Recovery Steps**:
```bash
# 1. Backup current state
kubectl get providers -o yaml > providers-backup.yaml
kubectl get providerconfigs -o yaml > providerconfigs-backup.yaml
kubectl get managed -o yaml > managed-resources-backup.yaml

# 2. Delete all provider revisions
kubectl delete providerrevision --all

# 3. Delete all providers
kubectl delete provider --all

# 4. Restart Crossplane
kubectl rollout restart deployment crossplane -n crossplane-system
kubectl rollout restart deployment crossplane-rbac-manager -n crossplane-system

# 5. Wait for Crossplane to stabilize
kubectl wait --for=condition=ready pod -l app=crossplane -n crossplane-system --timeout=300s

# 6. Sync ArgoCD Crossplane application
kubectl patch application dev-platform-crossplane -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# 7. Wait for providers to install (5-10 minutes)
kubectl get providers -w

# 8. Verify provider health
kubectl get providers
kubectl get providerconfigs

# 9. Reconcile managed resources
for resource in $(kubectl get managed -o name); do
  kubectl annotate $resource crossplane.io/paused=false --overwrite
done
```

---

### Node Replacement Procedure

**Scenario**: Node needs to be replaced due to issues

**Safe Replacement Steps**:
```bash
# 1. Cordon node to prevent new pods
kubectl cordon [node-name]

# 2. Drain node gracefully
kubectl drain [node-name] \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=300 \
  --timeout=600s

# 3. Verify pods rescheduled
kubectl get pods --all-namespaces -o wide | grep [node-name]
# Should show no pods except DaemonSets

# 4. Terminate instance (AWS Console or CLI)
aws ec2 terminate-instances --instance-ids [instance-id]

# 5. Wait for Auto Scaling Group to launch replacement
# Monitor:
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names [asg-name]

# 6. Verify new node joined
kubectl get nodes -w

# 7. Uncordon new node (if needed)
kubectl uncordon [new-node-name]
```

---

## Preventive Measures

### Monitoring and Alerting

#### Essential Metrics to Monitor
```yaml
cluster_health:
  - node_status
  - node_cpu_usage > 80%
  - node_memory_usage > 85%
  - node_disk_usage > 80%
  - pod_restarts > 5 per hour

argocd_health:
  - application_sync_status != "Synced"
  - application_health_status != "Healthy"
  - sync_failures > 0

crossplane_health:
  - provider_status != "Healthy"
  - managed_resource_status != "Ready"
  - reconciliation_failures > 0

spot_instance_monitoring:
  - spot_interruption_warnings
  - node_termination_events
  - pod_evictions
```

#### Setup Prometheus Alerts
```yaml
# Example AlertManager configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-alerts
  namespace: monitoring
data:
  alerts.yaml: |
    groups:
    - name: argocd
      rules:
      - alert: ArgoCDApplicationOutOfSync
        expr: argocd_app_info{sync_status!="Synced"} > 0
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "ArgoCD application {{ $labels.name }} is out of sync"

    - name: crossplane
      rules:
      - alert: CrossplaneProviderUnhealthy
        expr: crossplane_provider_health{health_status!="Healthy"} > 0
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Crossplane provider {{ $labels.provider }} is unhealthy"

    - name: nodes
      rules:
      - alert: NodeMemoryHigh
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Node {{ $labels.instance }} memory usage > 85%"
```

---

### Backup and Restore Procedures

#### Critical Resources to Backup

**Daily Backups**:
```bash
#!/bin/bash
# backup-cluster-state.sh

BACKUP_DIR="./backups/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# ArgoCD Applications
kubectl get applications -n argocd -o yaml > $BACKUP_DIR/argocd-applications.yaml

# Crossplane Resources
kubectl get providers -o yaml > $BACKUP_DIR/crossplane-providers.yaml
kubectl get providerconfigs -o yaml > $BACKUP_DIR/crossplane-providerconfigs.yaml
kubectl get managed -o yaml > $BACKUP_DIR/crossplane-managed-resources.yaml
kubectl get composite -o yaml > $BACKUP_DIR/crossplane-composite-resources.yaml

# ConfigMaps and Secrets (excluding sensitive data)
kubectl get configmaps --all-namespaces -o yaml > $BACKUP_DIR/configmaps.yaml

# Persistent Volume Claims
kubectl get pvc --all-namespaces -o yaml > $BACKUP_DIR/pvcs.yaml

# Helm Releases
helm list --all-namespaces -o yaml > $BACKUP_DIR/helm-releases.yaml

echo "Backup completed: $BACKUP_DIR"
```

**Setup Automated Backups with Velero**:
```bash
# Install Velero
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=portal-kombat-velero-backups \
  --set configuration.backupStorageLocation.config.region=us-east-2 \
  --set serviceAccount.server.annotations."eks\.amazonaws\.com/role-arn"=arn:aws:iam::[account]:role/velero-role

# Schedule daily backup
velero schedule create daily-backup \
  --schedule="0 2 * * *" \
  --include-namespaces argocd,crossplane-system \
  --ttl 720h
```

---

### Health Checks and Validation

#### Pre-Deployment Validation Script
```bash
#!/bin/bash
# pre-deployment-check.sh

echo "=== Cluster Health Check ==="

# 1. Check node status
echo "Checking nodes..."
if kubectl get nodes | grep -v Ready; then
  echo "❌ Some nodes are not ready"
  exit 1
fi
echo "✅ All nodes ready"

# 2. Check ArgoCD applications
echo "Checking ArgoCD applications..."
OUT_OF_SYNC=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.status.sync.status!="Synced")].metadata.name}')
if [ -n "$OUT_OF_SYNC" ]; then
  echo "⚠️  Applications out of sync: $OUT_OF_SYNC"
fi

# 3. Check Crossplane providers
echo "Checking Crossplane providers..."
UNHEALTHY=$(kubectl get providers -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Healthy")].status!="True")].metadata.name}')
if [ -n "$UNHEALTHY" ]; then
  echo "❌ Unhealthy providers: $UNHEALTHY"
  exit 1
fi
echo "✅ All providers healthy"

# 4. Check pod status
echo "Checking pod status..."
FAILING_PODS=$(kubectl get pods --all-namespaces --field-selector=status.phase!=Running,status.phase!=Succeeded -o jsonpath='{.items[*].metadata.name}')
if [ -n "$FAILING_PODS" ]; then
  echo "❌ Failing pods: $FAILING_PODS"
  exit 1
fi
echo "✅ All pods healthy"

# 5. Check resource usage
echo "Checking resource usage..."
kubectl top nodes | awk 'NR>1 {if ($3 > 80 || $5 > 85) {print "⚠️  High resource usage on " $1; exit 1}}'
echo "✅ Resource usage normal"

echo "=== All checks passed ==="
```

---

### Security Best Practices

#### Network Policies
```yaml
# Restrict Crossplane provider egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: crossplane-provider-egress
  namespace: crossplane-system
spec:
  podSelector:
    matchLabels:
      pkg.crossplane.io/provider: ""
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS only
  - to:
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53  # DNS
```

#### RBAC Audit
```bash
# List all ClusterRoleBindings
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.subjects[].kind=="ServiceAccount") | .metadata.name'

# Check for overly permissive roles
kubectl get clusterroles -o json | \
  jq -r '.items[] | select(.rules[].verbs[] | contains("*")) | .metadata.name'

# Audit Crossplane permissions
kubectl auth can-i --list --as=system:serviceaccount:crossplane-system:crossplane -n crossplane-system
```

---

## Escalation Procedures

### Severity Levels

#### P1 - Critical (Immediate Response)
**Conditions**:
- Cluster API unreachable
- Multiple nodes down
- All ArgoCD applications failing
- Data loss imminent
- Production services completely down

**Response**:
- Immediate page on-call engineer
- Notify platform team lead within 15 minutes
- Engage AWS support (if EKS issue)
- Status page update within 30 minutes
- Hourly updates to stakeholders

**Resolution SLA**: 1 hour

---

#### P2 - High (Urgent Response)
**Conditions**:
- Single node failure
- ArgoCD application stuck OutOfSync
- Crossplane provider unhealthy
- Performance degradation
- SPOT interruptions affecting workloads

**Response**:
- Notify on-call engineer
- Escalate to senior engineer if not resolved in 1 hour
- Status update within 2 hours
- Daily stakeholder updates

**Resolution SLA**: 4 hours

---

#### P3 - Medium (Normal Response)
**Conditions**:
- Non-critical pods restarting
- Minor configuration drift
- Monitoring alerts
- Resource usage warnings

**Response**:
- Create ticket for appropriate team
- Assign to next business day if after hours
- No immediate escalation required

**Resolution SLA**: 8 hours (business hours)

---

### Contact Information

```yaml
teams:
  platform_team:
    primary: "platform-oncall@company.com"
    secondary: "platform-lead@company.com"
    slack: "#platform-incidents"

  devops_team:
    primary: "devops-oncall@company.com"
    slack: "#devops-incidents"

  argocd_experts:
    primary: "gitops-team@company.com"
    slack: "#gitops-help"

  crossplane_experts:
    primary: "infrastructure-team@company.com"
    slack: "#crossplane-help"

aws_support:
  enterprise_support: "1-800-AWS-SUPPORT"
  account_manager: "aws-tam@company.com"
  support_portal: "https://console.aws.amazon.com/support"
```

---

## Appendix

### Useful One-Liners

```bash
# Find pods consuming most memory
kubectl top pods --all-namespaces --sort-by=memory | head -10

# Find pods with most restarts
kubectl get pods --all-namespaces --sort-by='.status.containerStatuses[0].restartCount' -o json | \
  jq -r '.items[] | "\(.metadata.namespace)\t\(.metadata.name)\t\(.status.containerStatuses[0].restartCount)"' | \
  sort -k3 -nr | head -10

# Count pods by namespace
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | .metadata.namespace' | sort | uniq -c | sort -nr

# Find pods without resource limits
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.containers[].resources.limits == null) |
  "\(.metadata.namespace)\t\(.metadata.name)"'

# Get all PVCs with size and status
kubectl get pvc --all-namespaces -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
STATUS:.status.phase,\
CAPACITY:.status.capacity.storage,\
STORAGECLASS:.spec.storageClassName

# Check certificate expiration
kubectl get certificates --all-namespaces -o json | \
  jq -r '.items[] | "\(.metadata.name)\t\(.status.notAfter)"'

# Find services without endpoints
kubectl get svc --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.clusterIP != "None") |
  "\(.metadata.namespace)\t\(.metadata.name)"' | \
  while read ns svc; do
    if ! kubectl get endpoints -n $ns $svc -o jsonpath='{.subsets}' | grep -q .; then
      echo "No endpoints: $ns/$svc"
    fi
  done
```

---

### Debugging Container Images

```bash
# Use debug container for troubleshooting
kubectl debug [pod-name] -n [namespace] -it --image=nicolaka/netshoot

# Copy files from crashed pod
kubectl cp [namespace]/[pod-name]:/path/to/file ./local-file

# Check image vulnerabilities (if trivy installed)
kubectl get pods -n [namespace] -o jsonpath='{.items[*].spec.containers[*].image}' | \
  tr ' ' '\n' | sort -u | while read img; do
    echo "Scanning: $img"
    trivy image $img
  done
```

---

### Log Collection Scripts

```bash
#!/bin/bash
# collect-logs.sh - Gather logs for support investigation

NAMESPACE=${1:-crossplane-system}
OUTPUT_DIR="logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p $OUTPUT_DIR

# Collect pod logs
for pod in $(kubectl get pods -n $NAMESPACE -o name); do
  echo "Collecting logs for $pod"
  kubectl logs -n $NAMESPACE $pod --all-containers=true > \
    $OUTPUT_DIR/$(basename $pod).log 2>&1
done

# Collect events
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' > \
  $OUTPUT_DIR/events.txt

# Collect resource states
kubectl get all -n $NAMESPACE -o yaml > $OUTPUT_DIR/resources.yaml

# Create tarball
tar -czf $OUTPUT_DIR.tar.gz $OUTPUT_DIR
echo "Logs collected: $OUTPUT_DIR.tar.gz"
```

---

### Additional Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Troubleshooting](https://kubernetes.io/docs/tasks/debug/)
- [AWS Support](https://console.aws.amazon.com/support)

---

**Document Version**: 1.0
**Last Reviewed**: 2025-11-03
**Next Review**: 2025-12-03
**Maintainer**: Platform Engineering Team
