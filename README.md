# Portal Kombat

A GitOps repository for managing AWS infrastructure using Crossplane via ArgoCD.

## What is This?

This repository uses:
- **ArgoCD** for GitOps continuous deployment
- **Crossplane** for declarative AWS infrastructure provisioning
- **Kubernetes** as the control plane

Everything in this repo gets automatically deployed to your Kubernetes cluster via ArgoCD. Infrastructure changes are made by committing to Git.

## Repository Structure

```
portal-kombat/
├── platform/              # Crossplane XRDs and Compositions (reusable infrastructure APIs)
├── environments/          # Environment-specific configs (dev, staging, prod)
│   └── dev/
│       ├── argocd/        # ArgoCD Applications
│       ├── infrastructure/# Infrastructure claims (VPC, EKS, S3, etc.)
│       ├── platform/      # Platform services (monitoring, ingress)
│       └── workloads/     # Application deployments
├── shared/                # Shared resources (IAM, provider configs)
└── docs/                  # Documentation
```

## Quick Start

### Prerequisites
- EKS cluster running
- ArgoCD installed
- kubectl configured
- AWS IAM configured (IRSA)

### Deploy Everything

```bash
# Deploy the root application (App of Apps)
kubectl apply -f environments/dev/argocd/root-app.yaml

# Watch ArgoCD deploy everything
kubectl get applications -n argocd -w
```

That's it! ArgoCD will now deploy:
1. Crossplane and AWS providers
2. Infrastructure definitions (XRDs, Compositions)
3. Your infrastructure (VPCs, EKS, S3 buckets, etc.)
4. Platform services (monitoring, ingress)
5. Your applications

## How to Use

### Create Infrastructure

**Option 1: Use a Composition (Platform API)**

```yaml
# environments/dev/infrastructure/storage/my-bucket.yaml
apiVersion: aws.platform.example/v1alpha1
kind: ObjectStorage
metadata:
  name: my-app-bucket
spec:
  parameters:
    bucketName: my-unique-bucket-name
    region: us-east-2
    versioning: true
    environment: dev
```

**Option 2: Use Managed Resources (Direct AWS)**

```yaml
# environments/dev/infrastructure/storage/my-bucket.yaml
apiVersion: s3.aws.crossplane.io/v1beta1
kind: Bucket
metadata:
  name: my-bucket
spec:
  forProvider:
    region: us-east-2
  providerConfigRef:
    name: default
```

Commit and push - ArgoCD deploys automatically!

### Deploy an Application

1. Add manifests to `environments/dev/workloads/my-app/`
2. Create an ArgoCD Application in `environments/dev/argocd/workload-apps.yaml`
3. Commit and push

### Add a New Environment

```bash
# Copy dev structure
cp -r environments/dev environments/staging

# Update configs (bucket names, cluster names, etc.)
# Update ArgoCD apps to point to staging paths

# Deploy
kubectl apply -f environments/staging/argocd/root-app.yaml
```

## Documentation

- **[Architecture](docs/ARCHITECTURE.md)** - Detailed explanation of the repository structure
- **[Quick Start](docs/QUICK-START.md)** - Step-by-step getting started guide
- **[IAM Setup](shared/managed-resources/iam-roles/SETUP-INSTRUCTIONS.md)** - AWS IAM configuration

## Key Concepts

### Crossplane
Crossplane turns your Kubernetes cluster into a universal control plane for cloud infrastructure. Instead of using Terraform or CloudFormation, you define infrastructure as Kubernetes resources.

### XRDs (CompositeResourceDefinitions)
Define custom APIs for your infrastructure. Example: "ObjectStorage" API that users can consume without knowing AWS details.

### Compositions
Implement the XRDs with actual cloud resources. Example: "ObjectStorage" composition creates an S3 bucket with encryption, versioning, and lifecycle policies.

### Claims
Instances of XRDs. Example: "I want an ObjectStorage with these parameters."

### GitOps with ArgoCD
Every change is made in Git. ArgoCD watches the repository and automatically syncs changes to the cluster.

## Examples

See `environments/dev/infrastructure/` for working examples of:
- S3 buckets
- VPCs
- EKS clusters
- RDS databases

## Troubleshooting

### Check ArgoCD Status
```bash
kubectl get applications -n argocd
argocd app list
```

### Check Crossplane Resources
```bash
kubectl get xrd
kubectl get compositions
kubectl get objectstorage
```

### View Logs
```bash
# Crossplane providers
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3

# ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

### Common Issues

**Claim not ready**: Check provider logs and AWS IAM permissions
**ArgoCD sync failed**: Check the application status with `argocd app get <app-name>`
**AWS forbidden errors**: See `shared/managed-resources/iam-roles/SETUP-INSTRUCTIONS.md`

## Contributing

1. Create a feature branch
2. Make changes in `environments/dev/` first
3. Test the changes
4. Create PR
5. After merge, promote to staging/prod

## Project Status

**Current State**: Development environment configured
**Next Steps**:
- Add staging environment
- Add production environment
- Create more XRDs and Compositions (VPC, EKS, RDS)
- Add Kustomize for environment overlays

## Links

- [Crossplane Docs](https://docs.crossplane.io/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [AWS Provider Docs](https://marketplace.upbound.io/providers/upbound/provider-aws/)
