# Platform Services Deployment Guide

Complete guide for deploying platform services (Cert-Manager, External DNS, nginx-ingress, Karpenter) using Terraform and ArgoCD.

## Overview

This guide covers:
1. Creating AWS infrastructure with Terraform
2. Deploying platform services via ArgoCD
3. Verifying deployments
4. Troubleshooting common issues

## Prerequisites

- ✅ EKS cluster `raiden-control-plane` running
- ✅ OIDC provider configured on EKS
- ✅ ArgoCD deployed and accessible
- ✅ AWS CLI configured with admin credentials
- ✅ Terraform >= 1.5.0 installed
- ✅ kubectl access to cluster

## Architecture

The deployment follows this pattern:

```
Terraform (AWS Infrastructure)
    ↓
    Creates: IAM roles, SQS queue, EventBridge rules, tags
    ↓
ArgoCD (Kubernetes Deployments)
    ↓
    Deploys in order:
    1. Cert-Manager (sync-wave: 10)
    2. External DNS (sync-wave: 20)
    3. nginx-ingress (sync-wave: 30)
    4. Karpenter (sync-wave: 40)
```

## Phase 1: Create AWS Infrastructure with Terraform

### Step 1: Navigate to Terraform Directory

```bash
cd bootstrap/terraform
```

### Step 2: Get Your OIDC Provider ID

```bash
# Get OIDC provider ID (last part of the issuer URL)
aws eks describe-cluster --name raiden-control-plane \
  --query "cluster.identity.oidc.issuer" \
  --output text | cut -d'/' -f5
```

Expected output: `31F74548D0C0D4910526F1FBE62C72B5`

### Step 3: Create terraform.tfvars

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
cluster_name     = "raiden-control-plane"
aws_region       = "us-east-2"
aws_account_id   = "654654563406"
oidc_provider_id = "31F74548D0C0D4910526F1FBE62C72B5"

# TODO: Update with your actual hosted zone IDs in production
external_dns_hosted_zone_ids = ["*"]

tags = {
  Environment = "dev"
  ManagedBy   = "Terraform"
  Project     = "portal-kombat"
  Cluster     = "raiden-control-plane"
}
```

### Step 4: Initialize Terraform

```bash
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

### Step 5: Review the Plan

```bash
terraform plan
```

Review what will be created:
- ✅ 2 IAM roles with policies (External DNS, Karpenter Controller)
- ✅ 1 IAM role with instance profile (Karpenter Node)
- ✅ 1 SQS queue
- ✅ 4 EventBridge rules with targets
- ✅ Tags on subnets and security groups

### Step 6: Apply Terraform Configuration

```bash
terraform apply
```

Type `yes` to confirm.

Expected output:
```
Apply complete! Resources: 17 added, 0 changed, 0 destroyed.

Outputs:

external_dns_role_arn = "arn:aws:iam::654654563406:role/external-dns-role"
karpenter_controller_role_arn = "arn:aws:iam::654654563406:role/karpenter_controller_role"
karpenter_node_role_name = "karpenter_node_role"
karpenter_interruption_queue_name = "raiden-control-plane"
...
```

### Step 7: Save Outputs

```bash
# Save all outputs to a file for reference
terraform output > terraform-outputs.txt

# Or get specific outputs
terraform output external_dns_role_arn
terraform output karpenter_controller_role_arn
terraform output karpenter_node_role_name
terraform output karpenter_interruption_queue_name
```

## Phase 2: Update Kubernetes Configurations

### Step 1: Verify Output Values

The Terraform outputs should already match your Kubernetes manifests:

**Check External DNS:**
```bash
grep "eks.amazonaws.com/role-arn" environments/dev/platform/external-dns/values.yaml
```

Should show: `arn:aws:iam::654654563406:role/external-dns-role`

**Check Karpenter Controller:**
```bash
grep "eks.amazonaws.com/role-arn" environments/dev/platform/karpenter/values.yaml
```

Should show: `arn:aws:iam::654654563406:role/karpenter_controller_role`

**Check Karpenter NodeClass:**
```bash
grep "role:" environments/dev/platform/karpenter/nodeclass.yaml
```

Should show: `role: karpenter_node_role`

### Step 2: Update Domain Names (TODO)

Before deploying, update these files with your actual domain:

**External DNS** (`environments/dev/platform/external-dns/values.yaml:12`):
```yaml
domainFilters:
  - yourcompany.com  # TODO: Change to your domain
```

**nginx-ingress Public** (`environments/dev/platform/nginx-ingress/values.yaml:22`):
```yaml
external-dns.alpha.kubernetes.io/hostname: portal-kombat.yourcompany.com  # TODO: Change domain
```

**nginx-ingress Internal** (`environments/dev/platform/nginx-ingress/values.yaml:95`):
```yaml
external-dns.alpha.kubernetes.io/hostname: portal-internal.yourcompany.com  # TODO: Change domain
```

**Cert-Manager ClusterIssuers** (already updated with your email):
```yaml
email: austin.carter@intelerad.com  # ✓ Already set
```

## Phase 3: Deploy via ArgoCD

### Step 1: Deploy ArgoCD Application

```bash
kubectl apply -f environments/dev/argocd/k8s-platform-services-apps.yaml
```

Expected output:
```
application.argoproj.io/dev-platform-cert-manager created
application.argoproj.io/dev-platform-external-dns created
application.argoproj.io/dev-platform-nginx-ingress created
application.argoproj.io/dev-platform-karpenter created
```

### Step 2: Watch ArgoCD Sync

```bash
# Watch all applications
kubectl get applications -n argocd -w

# Or watch in separate terminal
watch -n 2 'kubectl get applications -n argocd'
```

Expected progression:
```
NAME                          SYNC STATUS   HEALTH STATUS
dev-platform-cert-manager     Synced        Healthy       (wave: 10)
dev-platform-external-dns     Synced        Healthy       (wave: 20)
dev-platform-nginx-ingress    Synced        Healthy       (wave: 30)
dev-platform-karpenter        Synced        Healthy       (wave: 40)
```

### Step 3: Monitor Pod Deployments

**Terminal 1: Cert-Manager**
```bash
watch -n 2 'kubectl get pods -n cert-manager'
```

**Terminal 2: External DNS**
```bash
watch -n 2 'kubectl get pods -n external-dns'
```

**Terminal 3: nginx-ingress**
```bash
watch -n 2 'kubectl get pods -n ingress-nginx'
```

**Terminal 4: Karpenter**
```bash
watch -n 2 'kubectl get pods -n karpenter'
```

## Phase 4: Verification

### Cert-Manager Verification

```bash
# Check pods
kubectl get pods -n cert-manager

# Expected: 3 pods running (cert-manager, webhook, cainjector)

# Check ClusterIssuers
kubectl get clusterissuers

# Expected:
# NAME                  READY   AGE
# letsencrypt-prod      True    2m
# letsencrypt-staging   True    2m
# selfsigned            True    2m

# Test certificate creation
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-certificate
  namespace: default
spec:
  secretName: test-tls
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
  dnsNames:
  - test.example.com
EOF

# Check certificate
kubectl get certificate test-certificate -n default
kubectl describe certificate test-certificate -n default

# Cleanup test
kubectl delete certificate test-certificate -n default
```

### External DNS Verification

```bash
# Check pods
kubectl get pods -n external-dns

# Expected: 1 pod running

# Check logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=50

# Expected logs showing:
# - "Desired change: CREATE test.yourcompany.com A"
# - No errors about IAM permissions

# Check service account annotations
kubectl get sa external-dns -n external-dns -o yaml | grep eks.amazonaws.com

# Expected: eks.amazonaws.com/role-arn: arn:aws:iam::654654563406:role/external-dns-role
```

### nginx-ingress Verification

```bash
# Check pods (should have 2 public + 2 internal = 4 total)
kubectl get pods -n ingress-nginx

# Check services
kubectl get svc -n ingress-nginx

# Expected: 2 LoadBalancer services (public and internal)
# NAME                                      TYPE           EXTERNAL-IP
# public-ingress-nginx-controller           LoadBalancer   xxx.elb.amazonaws.com
# internal-ingress-nginx-controller         LoadBalancer   internal-xxx.elb.amazonaws.com

# Check IngressClasses
kubectl get ingressclasses

# Expected:
# NAME             CONTROLLER                    DEFAULT
# nginx            k8s.io/ingress-nginx          true
# nginx-internal   k8s.io/ingress-nginx-internal false

# Get public NLB address
kubectl get svc -n ingress-nginx public-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test public ingress (should return 404 - no backend configured yet)
curl -I http://$(kubectl get svc -n ingress-nginx public-ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

### Karpenter Verification

```bash
# Check pods (should have 2 replicas for HA)
kubectl get pods -n karpenter

# Expected: 2 pods running

# Check service account annotations
kubectl get sa karpenter -n karpenter -o yaml | grep eks.amazonaws.com

# Expected: eks.amazonaws.com/role-arn: arn:aws:iam::654654563406:role/karpenter_controller_role

# Check NodePools
kubectl get nodepools

# Expected: 4 NodePools
# NAME                      NODECLASS   NODES   READY   AGE
# default                   default     0             2m
# crossplane-providers      default     0             2m
# port-action-runners       default     0             2m
# control-plane-critical    default     0             2m

# Check EC2NodeClass
kubectl get ec2nodeclasses

# Expected:
# NAME      READY   AGE
# default   True    2m

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50

# Expected logs showing:
# - "Registered nodeclaim"
# - No errors about IAM permissions
# - "Watching for interruption events from sqs queue"
```

### Test Karpenter Node Provisioning

Create a test deployment to trigger node provisioning:

```bash
# Create test deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: default
spec:
  replicas: 0
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      containers:
      - name: inflate
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
        resources:
          requests:
            cpu: 1
            memory: 1.5Gi
EOF

# Scale up to trigger provisioning
kubectl scale deployment inflate --replicas=5

# Watch Karpenter create nodes
kubectl get nodes -w

# Expected: New nodes appear with name pattern: karpenter-*

# Check node labels
kubectl get nodes -l karpenter.sh/nodepool=default

# Cleanup test deployment
kubectl delete deployment inflate
```

## Troubleshooting

### ArgoCD Application Not Syncing

```bash
# Check application details
kubectl describe application dev-platform-cert-manager -n argocd

# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Force sync
kubectl patch application dev-platform-cert-manager -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### External DNS Permission Errors

```bash
# Check logs
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=100

# Common error: "AccessDenied: User is not authorized"
# Fix: Verify IAM role ARN in service account matches Terraform output

# Check service account
kubectl get sa external-dns -n external-dns -o yaml

# Should show:
# annotations:
#   eks.amazonaws.com/role-arn: arn:aws:iam::654654563406:role/external-dns-role
```

### Karpenter Not Provisioning Nodes

```bash
# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Common issues:

# 1. IAM permissions
# Error: "AccessDenied: User is not authorized to perform: ec2:RunInstances"
# Fix: Verify Karpenter controller role ARN

# 2. No capacity
# Error: "no instance types satisfy requirements"
# Fix: Check NodePool requirements and availability zones

# 3. Subnet/SG tags missing
# Error: "no subnets found"
# Fix: Verify Terraform tagged subnets correctly
kubectl get ec2nodeclasses default -o yaml | grep -A5 subnetSelectorTerms

# 4. Instance profile missing
# Error: "instance profile not found"
# Fix: Verify instance profile was created
aws iam get-instance-profile --instance-profile-name KarpenterNodeInstanceProfile-raiden-control-plane
```

### nginx-ingress Not Getting External IP

```bash
# Check service
kubectl describe svc -n ingress-nginx public-ingress-nginx-controller

# Common issues:

# 1. VPC/Subnet configuration
# Check events for errors:
# Events:
#   Type     Reason                  Message
#   Warning  SyncLoadBalancerFailed  Error syncing load balancer

# 2. AWS Load Balancer Controller not working
# Check if AWS LB Controller is running:
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# 3. Service annotations incorrect
# Verify annotations:
kubectl get svc -n ingress-nginx public-ingress-nginx-controller -o yaml | grep annotations -A10
```

### Certificate Manager Not Creating Certificates

```bash
# Check ClusterIssuer
kubectl describe clusterissuer letsencrypt-prod

# Check certificate request
kubectl describe certificaterequest <cert-name>

# Common issues:

# 1. HTTP01 challenge failing
# Error: "Waiting for HTTP-01 challenge propagation"
# Fix: Ensure nginx-ingress is working and accessible

# 2. Rate limiting
# Error: "too many certificates already issued"
# Fix: Use letsencrypt-staging for testing

# Check cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=100
```

## Rollback Procedures

### Rollback ArgoCD Deployment

```bash
# Delete ArgoCD application (doesn't delete resources)
kubectl delete -f environments/dev/argocd/k8s-platform-services-apps.yaml

# Or delete specific application
kubectl delete application dev-platform-karpenter -n argocd
```

### Rollback Terraform

```bash
cd bootstrap/terraform

# Destroy all resources
terraform destroy

# Or target specific module
terraform destroy -target=module.karpenter_controller_irsa
```

## Post-Deployment Tasks

### 1. Update DNS Records

If using External DNS, create a test ingress:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: test.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-service
            port:
              number: 80
EOF

# Check External DNS created Route53 record
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns --tail=20
```

### 2. Test TLS Certificate

Create a test certificate with Let's Encrypt staging:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-tls
  namespace: default
spec:
  secretName: test-tls-secret
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - test.yourcompany.com
EOF

# Check certificate status
kubectl get certificate test-tls
kubectl describe certificate test-tls
```

### 3. Configure Application Workloads

Update your application deployments to use:
- **NodeSelector/Tolerations** for Karpenter NodePools
- **IngressClass** `nginx` for public services
- **IngressClass** `nginx-internal` for internal services
- **cert-manager annotations** for TLS

Example:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      # Use Karpenter default NodePool
      nodeSelector:
        karpenter.sh/nodepool: default
      # Or use dedicated NodePool with toleration
      tolerations:
      - key: workload-type
        value: port-runners
        effect: NoSchedule
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - myapp.yourcompany.com
    secretName: myapp-tls
  rules:
  - host: myapp.yourcompany.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-app
            port:
              number: 80
```

## Monitoring

### ArgoCD UI

```bash
# Get ArgoCD password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open: https://localhost:8080
# Username: admin
# Password: <from above>
```

### Grafana Dashboards

If Prometheus stack is deployed, import these dashboards:
- Cert-Manager: Dashboard ID 11001
- nginx-ingress: Dashboard ID 9614
- Karpenter: Dashboard ID 19870

### Useful Commands

```bash
# Check all platform services health
kubectl get pods -n cert-manager && \
kubectl get pods -n external-dns && \
kubectl get pods -n ingress-nginx && \
kubectl get pods -n karpenter

# Check Karpenter node provisioning
kubectl get nodes -l karpenter.sh/nodepool

# Check certificates
kubectl get certificates --all-namespaces

# Check ingresses
kubectl get ingress --all-namespaces

# Check NodePools capacity
kubectl get nodepools -o custom-columns=\
NAME:.metadata.name,\
NODECLASS:.spec.template.spec.nodeClassRef.name,\
CPU:.status.resources.cpu,\
MEMORY:.status.resources.memory
```

## Next Steps

1. **Configure Port.io Integration**: Deploy Port.io action runners with NodePool tolerations
2. **Set up Monitoring**: Configure Prometheus alerts for platform services
3. **Backup Configuration**: Set up Velero for cluster backup
4. **Security Hardening**: Implement Network Policies and Pod Security Standards
5. **Cost Optimization**: Monitor Karpenter provisioning costs and adjust NodePool configurations

## Support

For issues or questions:
- Check logs: `kubectl logs -n <namespace> -l app.kubernetes.io/name=<app>`
- Review ArgoCD events: `kubectl get events -n argocd --sort-by='.lastTimestamp'`
- Check AWS CloudTrail for IAM permission issues
- Review Terraform plan: `terraform plan`
