# Quick Start Guide

## Prerequisites

- EKS cluster running
- ArgoCD installed in the cluster
- kubectl configured
- AWS credentials configured (IRSA for Crossplane)

## Step 1: Bootstrap ArgoCD with the Dev Environment

Deploy the root application that will manage everything:

```bash
kubectl apply -f environments/dev/argocd/root-app.yaml
```

This creates an "App of Apps" that deploys:
1. Crossplane platform (providers, XRDs, compositions)
2. Infrastructure claims (VPC, EKS, S3, etc.)
3. Platform services (monitoring, ingress)
4. Application workloads (s3reader, etc.)

## Step 2: Watch ArgoCD Deploy Everything

```bash
# Watch applications sync
kubectl get applications -n argocd -w

# Check for any sync errors
argocd app list
```

## Step 3: Verify Crossplane is Working

```bash
# Check providers are healthy
kubectl get providers

# Check XRDs are installed
kubectl get xrd

# Check compositions are available
kubectl get compositions

# Check provider configs
kubectl get providerconfigs -A
```

## Step 4: Create Your First Infrastructure Resource

### Option A: Using a Composition (Recommended)

Create a claim for an S3 bucket using the platform API:

```bash
# Apply the example claim
kubectl apply -f environments/dev/infrastructure/storage/example-bucket-claim.yaml

# Watch it get created
kubectl get objectstorage -w

# Check the actual AWS bucket was created
kubectl get buckets

# View details
kubectl describe objectstorage my-app-data-bucket
```

### Option B: Using a Managed Resource (Direct)

Create an S3 bucket directly without compositions:

```yaml
# Save to: environments/dev/infrastructure/storage/direct-bucket.yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: my-direct-bucket
  annotations:
    crossplane.io/external-name: portal-kombat-dev-direct-12345
spec:
  forProvider:
    region: us-east-2
  providerConfigRef:
    name: default
  deletionPolicy: Delete
```

```bash
kubectl apply -f environments/dev/infrastructure/storage/direct-bucket.yaml
kubectl get bucket my-direct-bucket
```

## Step 5: Deploy an Application

Your applications live in `environments/dev/workloads/`. The s3reader app is already configured.

To deploy a new application:

1. Create the directory:
   ```bash
   mkdir -p environments/dev/workloads/my-app
   ```

2. Add your Kubernetes manifests:
   ```bash
   # Create deployment, service, etc.
   ```

3. Create an ArgoCD application:
   ```yaml
   # environments/dev/argocd/workload-apps.yaml
   ---
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: dev-workload-my-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: git@github.com:ims-platform-dev/portal-kombat.git
       targetRevision: main
       path: environments/dev/workloads/my-app
     destination:
       server: https://kubernetes.default.svc
       namespace: default
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

4. Commit and push - ArgoCD will auto-deploy!

## Common Tasks

### Adding a New Environment (Staging)

```bash
# 1. Copy the dev structure
cp -r environments/dev environments/staging

# 2. Update all bucket names, cluster names to be unique
# Find and replace: dev -> staging, update unique identifiers

# 3. Create staging provider config
cp shared/configs/provider-configs/dev-account.yaml \
   shared/configs/provider-configs/staging-account.yaml

# 4. Update the staging ArgoCD apps to point to staging paths
# Edit environments/staging/argocd/*.yaml

# 5. Deploy
kubectl apply -f environments/staging/argocd/root-app.yaml
```

### Creating a New XRD and Composition

See `docs/CREATING-COMPOSITIONS.md` for detailed guide.

Quick example:

1. Define the API (XRD):
   ```bash
   vim platform/xrds/compute/xrd-ec2-instance.yaml
   ```

2. Create a composition:
   ```bash
   vim platform/compositions/compute/ec2-web-server.yaml
   ```

3. Create a claim in dev:
   ```bash
   vim environments/dev/infrastructure/compute/web-server-claim.yaml
   ```

4. Commit, push, let ArgoCD deploy!

### Updating Infrastructure

1. Edit the claim or managed resource:
   ```bash
   vim environments/dev/infrastructure/storage/example-bucket-claim.yaml
   ```

2. Commit and push:
   ```bash
   git add .
   git commit -m "Update bucket configuration"
   git push
   ```

3. ArgoCD automatically syncs (or manual sync in ArgoCD UI)

### Checking Logs

```bash
# ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Crossplane provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3

# Application logs
kubectl logs -n default -l app=s3reader
```

### Troubleshooting

**Claim stuck in "Not Ready" state:**
```bash
kubectl describe objectstorage my-app-data-bucket
# Check Events section for errors

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=100
```

**ArgoCD sync failed:**
```bash
argocd app get dev-infrastructure
# Check Status section

# View in UI
argocd app list
```

**AWS permissions issues:**
See `shared/managed-resources/iam-roles/SETUP-INSTRUCTIONS.md` for IAM configuration.

## Next Steps

- Read `docs/ARCHITECTURE.md` to understand the full structure
- Check `docs/ONBOARDING.md` for team onboarding guide
- Create your first custom composition
- Add staging and prod environments

## Getting Help

- Crossplane Docs: https://docs.crossplane.io/
- ArgoCD Docs: https://argo-cd.readthedocs.io/
- AWS Provider Docs: https://marketplace.upbound.io/providers/upbound/provider-aws/
