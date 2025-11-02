# Portal Kombat Naming Conventions

## Overview

This document defines naming conventions for Crossplane resources in the Portal Kombat platform. These conventions ensure consistency, readability, and maintainability across all environments.

## AWS Account Determination

**AWS accounts are determined by the combination of:**

1. **ProviderConfig Reference**: Each Composition references a specific `providerConfigRef.name`
2. **ProviderConfig**: Defines which AWS account to use via IRSA or role assumption
3. **Environment Deployment**: ArgoCD applications deploy claims to specific clusters

### Current ProviderConfigs

| Environment | ProviderConfig Name | AWS Account Access |
|-------------|-------------------|-------------------|
| dev | `default` | Direct IRSA to dev cluster account |
| prod | `child-dev-account` | Cross-account via role chain to production |
| management | `management-account` | Cross-account to management account |

### Example: Account Selection Flow

```yaml
# environments/dev/infrastructure/storage/my-bucket.yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: ObjectStorage
metadata:
  name: portal-kombat-user-data-bucket  # Kubernetes resource name
spec:
  compositionSelector:
    matchLabels:
      bucket-type: private
  parameters:
    bucketName: portal-kombat-dev-user-data-12345  # AWS resource name
```

This claim uses the `objectstorage-private` Composition, which references `providerConfigRef.name: default`, deploying to the dev AWS account.

## Naming Convention Standards

### General Rules

- **Use kebab-case** for all names (lowercase with hyphens)
- **Be descriptive** but concise
- **Include purpose** in the name
- **Avoid generic names** like `s3.yaml` or `bucket.yaml`
- **Use consistent prefixes** across environments

### Kubernetes Resource Names (metadata.name)

Pattern: `{project}-{purpose}-{resource-type}`

Where:
- `{project}`: `portal-kombat` (fixed prefix)
- `{purpose}`: Describes what the resource does (`user-data`, `app-logs`, `web-cluster`, etc.)
- `{resource-type}`: Optional suffix for clarity (`bucket`, `database`, `cluster`)

#### Examples

**Storage Resources:**
```yaml
metadata:
  name: portal-kombat-user-uploads-bucket
  name: portal-kombat-app-logs-bucket
  name: portal-kombat-backup-data-bucket
```

**Database Resources:**
```yaml
metadata:
  name: portal-kombat-app-database
  name: portal-kombat-user-sessions-database
  name: portal-kombat-analytics-database
```

**Compute Resources:**
```yaml
metadata:
  name: portal-kombat-web-cluster
  name: portal-kombat-api-cluster
  name: portal-kombat-worker-cluster
```

**Network Resources:**
```yaml
metadata:
  name: portal-kombat-web-network
  name: portal-kombat-database-network
  name: portal-kombat-load-balancer
```

### AWS Resource Names (spec.parameters.{resource}Name)

Pattern: `{project}-{env}-{purpose}-{unique-id}`

Where:
- `{project}`: `portal-kombat` (fixed prefix)
- `{env}`: Environment (`dev`, `staging`, `prod`)
- `{purpose}`: Same as metadata.name purpose
- `{unique-id}`: 5-digit random number for global uniqueness

#### Examples

**S3 Buckets:**
```yaml
spec:
  parameters:
    bucketName: portal-kombat-dev-user-uploads-67890
    bucketName: portal-kombat-prod-app-logs-12345
    bucketName: portal-kombat-staging-backup-data-99999
```

**RDS Databases:**
```yaml
spec:
  parameters:
    dbInstanceName: portal-kombat-dev-app-database-54321
    dbName: app_db  # Can be simple since instance name ensures uniqueness
```

**EKS Clusters:**
```yaml
spec:
  parameters:
    clusterName: portal-kombat-dev-web-cluster-11111
```

## Environment-Specific Patterns

### Development Environment

**Purpose:** Safe experimentation and testing
**Account:** Dev AWS account
**Naming:** Include `-dev-` in AWS resource names

```yaml
# Claim
metadata:
  name: portal-kombat-user-uploads-bucket
spec:
  parameters:
    bucketName: portal-kombat-dev-user-uploads-67890
    environment: dev
```

### Staging Environment

**Purpose:** Pre-production validation
**Account:** Staging AWS account (when available)
**Naming:** Include `-staging-` in AWS resource names

```yaml
metadata:
  name: portal-kombat-user-uploads-bucket
spec:
  parameters:
    bucketName: portal-kombat-staging-user-uploads-67890
    environment: staging
```

### Production Environment

**Purpose:** Live production systems
**Account:** Production AWS account
**Naming:** Include `-prod-` in AWS resource names

```yaml
metadata:
  name: portal-kombat-user-uploads-bucket
spec:
  parameters:
    bucketName: portal-kombat-prod-user-uploads-67890
    environment: prod
```

## File Organization and Naming

### Directory Structure

```
environments/{env}/infrastructure/
├── storage/
│   ├── portal-kombat-user-uploads-bucket.yaml
│   ├── portal-kombat-app-logs-bucket.yaml
│   └── portal-kombat-backup-data-bucket.yaml
├── database/
│   ├── portal-kombat-app-database.yaml
│   └── portal-kombat-analytics-database.yaml
├── compute/
│   ├── portal-kombat-web-cluster.yaml
│   └── portal-kombat-worker-cluster.yaml
└── network/
    ├── portal-kombat-web-network.yaml
    └── portal-kombat-load-balancer.yaml
```

### YAML File Names

File names should match the `metadata.name` of the primary resource:

```bash
# Good
portal-kombat-user-uploads-bucket.yaml

# Bad
bucket.yaml
s3-bucket.yaml
user-data-storage.yaml
```

## Connection Secrets

Connection secrets follow the same naming pattern:

```yaml
writeConnectionSecretToRef:
  name: portal-kombat-user-uploads-bucket-connection
  namespace: default
```

## Complete Examples

### S3 Bucket Claim

```yaml
---
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: ObjectStorage
metadata:
  name: portal-kombat-user-uploads-bucket
  namespace: default
spec:
  parameters:
    bucketName: portal-kombat-dev-user-uploads-67890
    region: us-east-2
    versioning: true
    encryption: AES256
    publicAccess: false
    environment: dev
  compositionSelector:
    matchLabels:
      bucket-type: private
  writeConnectionSecretToRef:
    name: portal-kombat-user-uploads-bucket-connection
    namespace: default
```

### Database Claim

```yaml
---
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: RelationalDatabase
metadata:
  name: portal-kombat-app-database
  namespace: default
spec:
  parameters:
    dbInstanceName: portal-kombat-dev-app-database-54321
    dbName: app_db
    engine: postgres
    engineVersion: "15"
    instanceClass: db.t3.micro
    allocatedStorage: 20
    environment: dev
  compositionSelector:
    matchLabels:
      database-type: postgres
  writeConnectionSecretToRef:
    name: portal-kombat-app-database-connection
    namespace: default
```

## Validation Checklist

When creating new resources, verify:

- [ ] `metadata.name` follows `{project}-{purpose}-{resource-type}` pattern
- [ ] AWS resource name includes environment and unique ID
- [ ] File name matches `metadata.name`
- [ ] Connection secret name follows naming convention
- [ ] Environment parameter matches deployment target
- [ ] No generic or abbreviated names used

## Migration Guide

For existing resources that don't follow these conventions:

1. **Keep existing AWS resources** (don't rename - could break dependencies)
2. **Update metadata.name** to follow new convention
3. **Update file names** to match new metadata.name
4. **Update any references** in other files or documentation

Example migration:

```yaml
# Before
metadata:
  name: my-s3-bucket
spec:
  parameters:
    bucketName: portal-kombat-dev-my-bucket-12345

# After
metadata:
  name: portal-kombat-app-data-bucket
spec:
  parameters:
    bucketName: portal-kombat-dev-my-bucket-12345  # Keep existing AWS name
```

## Tooling Support

Consider creating validation tools to enforce these conventions:

- **Pre-commit hooks** to validate YAML files
- **CI/CD checks** for naming compliance
- **Crossplane validation webhooks** for real-time enforcement

## Related Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Platform architecture overview
- [QUICK-START.md](QUICK-START.md) - Getting started guide
- [CLAUDE.md](../CLAUDE.md) - Development workflow guide
