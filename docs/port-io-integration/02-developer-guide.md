# Port.io Developer Guide

## Overview

This guide explains how developers can use Port.io to discover infrastructure resources and request new infrastructure for their applications.

## Accessing Port.io

### Login

1. Navigate to https://app.getport.io/
2. Sign in with SSO (Single Sign-On) using your company email
3. You'll be redirected to the Portal Kombat service catalog

### User Interface Overview

```
┌─────────────────────────────────────────────────────────────┐
│  Port.io - Portal Kombat Infrastructure Catalog             │
├──────────────┬──────────────────────────────────────────────┤
│              │                                               │
│  Navigation  │          Service Catalog                      │
│              │                                               │
│  📦 Catalog  │  🔍 Search: [Find infrastructure...]         │
│  🎯 Actions  │                                               │
│  📊 Dashboards│  Filters: Environment | Team | Status       │
│  📈 Analytics│                                               │
│              │  ┌─────────────────────────────────────────┐ │
│              │  │ S3 Bucket: user-uploads-bucket          │ │
│              │  │ Status: ● Healthy                       │ │
│              │  │ Environment: dev | Team: backend        │ │
│              │  │ Bucket: portal-kombat-dev-uploads-...  │ │
│              │  └─────────────────────────────────────────┘ │
│              │                                               │
│              │  ┌─────────────────────────────────────────┐ │
│              │  │ RDS Database: user-db                   │ │
│              │  │ Status: ● Healthy                       │ │
│              │  │ Environment: production | Team: backend │ │
│              │  └─────────────────────────────────────────┘ │
└──────────────┴──────────────────────────────────────────────┘
```

## Discovering Infrastructure

### Browsing the Catalog

**Filter by Blueprint (Resource Type)**:
- Click "Catalog" in left navigation
- Select filter: "Blueprint"
- Choose resource type:
  - `s3-bucket`: AWS S3 buckets
  - `object-storage-claim`: Crossplane storage claims
  - `rds-database`: Relational databases
  - `vpc`: Virtual private clouds
  - `eks-cluster`: Kubernetes clusters

**Filter by Environment**:
- Select filter: "Environment"
- Choose: `dev`, `staging`, `production`

**Filter by Team**:
- Select filter: "Team"
- Choose your team name

**Filter by Status**:
- Select filter: "Status"
- Choose: `Healthy`, `Degraded`, `Failed`, `Provisioning`

### Searching for Resources

**Search by Name**:
```
Search: user-uploads
Results: All resources with "user-uploads" in name or description
```

**Search by Property**:
```
Search: region:us-east-2
Results: All resources in us-east-2 region
```

**Search by Tag**:
```
Search: team:backend
Results: All resources owned by backend team
```

### Viewing Resource Details

Click on any resource to see:

**Overview Tab**:
- Resource name and status
- Created date and last modified
- Owning team and cost center
- Environment and region
- Current health status

**Properties Tab**:
- All resource configuration details
- AWS-specific properties (ARN, region, etc.)
- Crossplane-specific metadata

**Relations Tab**:
- Dependent applications
- Related infrastructure (VPC, cluster, etc.)
- Dependency graph visualization

**Activity Tab**:
- Creation events
- Status changes
- Recent modifications
- Audit trail

## Requesting New Infrastructure

### Self-Service Action: Provision S3 Bucket

#### Step 1: Navigate to Self-Service

1. Click "Self-Service" in left navigation
2. Find action: "Provision S3 Bucket"
3. Click "Execute"

#### Step 2: Fill in Request Form

**Required Fields**:
- **Bucket Purpose**: Business purpose (e.g., `user-uploads`, `backup-storage`, `logs`)
  - Format: lowercase, numbers, hyphens only
  - Example: `user-profile-images`

- **Environment**: Target environment
  - `dev`: Development (auto-approved)
  - `staging`: Pre-production (requires approval)
  - `production`: Production (requires approval + security review)

- **Team Name**: Your team identifier
  - Format: lowercase, numbers, hyphens only
  - Example: `backend-team`

**Optional Fields**:
- **Enable Versioning**: Protect against accidental deletions
  - Recommended: `true` for production
  - Default: `false`

- **Encryption Type**: Server-side encryption
  - `AES256`: Standard encryption (default)
  - `aws:kms`: KMS encryption (for compliance requirements)

- **Lifecycle Policy**: Automatic data management
  - `none`: No lifecycle management (default)
  - `transition-to-glacier-30d`: Move to Glacier after 30 days
  - `expire-old-versions-90d`: Delete old versions after 90 days

- **Public Read Access**: Allow public internet access
  - ⚠️ WARNING: Security risk, requires approval for production
  - Default: `false` (recommended)

- **Cost Center**: Billing attribution (optional)

- **Business Justification**: Why this bucket is needed
  - Required for staging and production
  - Include use case and expected data volume

#### Step 3: Review and Submit

1. Review all entered information
2. Check estimated costs (if available)
3. Click "Execute" to submit request

#### Step 4: Monitor Progress

**Port.io Run Status**:
- **In Progress**: Workflow running
- **Success**: Infrastructure provisioned
- **Failed**: Error occurred (check error message)

**Workflow Steps**:
1. Request validation (1-2 minutes)
2. Pull request creation (1-2 minutes)
3. Approval (dev: automatic, staging/prod: manual)
4. ArgoCD sync (2-5 minutes)
5. Crossplane provisioning (3-10 minutes)
6. Catalog update (1-2 minutes)

**Total Time**:
- Dev environment: 10-15 minutes (auto-approved)
- Staging/Production: 15-30 minutes (includes manual approval)

#### Step 5: Approval Process (Staging/Production Only)

**GitHub Pull Request Review**:
1. Platform Engineering team receives notification
2. Reviewer checks:
   - Bucket name follows conventions
   - Configuration meets security standards
   - Business justification adequate
   - No duplicate resources
3. Reviewer approves or requests changes
4. PR merged after approval

**Security Review (Production + Public Access)**:
1. Security team notified automatically
2. Additional security checklist reviewed
3. Public access risk assessment
4. Approval or denial with feedback

#### Step 6: Access Your Infrastructure

Once provisioned:

**Find in Catalog**:
- Navigate to Port.io → Catalog
- Search for your bucket purpose
- Click to view details

**Get Connection Information**:
- View "Properties" tab for bucket name and ARN
- Check "Relations" tab for associated secret
- Use Kubernetes secret for application configuration

**Example Kubernetes Secret Usage**:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
    - name: app
      image: my-app:latest
      env:
        - name: S3_BUCKET_NAME
          valueFrom:
            secretKeyRef:
              name: user-uploads-bucket-connection
              key: bucketName
        - name: S3_REGION
          valueFrom:
            secretKeyRef:
              name: user-uploads-bucket-connection
              key: region
```

## Common Workflows

### Workflow 1: Deploy Application with New S3 Bucket

```
1. Request S3 bucket via Port.io
   ↓
2. Wait for provisioning (10-15 minutes)
   ↓
3. Search catalog for bucket name
   ↓
4. Copy bucket name from Properties tab
   ↓
5. Update application deployment YAML
   ↓
6. Deploy application via ArgoCD
   ↓
7. Verify application can access bucket
```

### Workflow 2: Find Existing Infrastructure for Application

```
1. Open Port.io Catalog
   ↓
2. Filter by team: your-team
   ↓
3. Filter by environment: dev
   ↓
4. Browse available resources
   ↓
5. Click resource for details
   ↓
6. Check "Relations" tab for dependent apps
   ↓
7. Copy connection details from Properties tab
```

### Workflow 3: Troubleshoot Infrastructure Issues

```
1. Open Port.io Catalog
   ↓
2. Filter by status: Failed or Degraded
   ↓
3. Click failing resource
   ↓
4. Read status message in Overview tab
   ↓
5. Check Activity tab for recent changes
   ↓
6. View Relations tab for impacted applications
   ↓
7. Contact platform team with resource name
```

## Best Practices

### Naming Conventions

**Bucket Purpose**:
- ✅ Good: `user-profile-images`, `backup-database`, `application-logs`
- ❌ Bad: `bucket1`, `myBucket`, `test_bucket`

**Team Names**:
- ✅ Good: `backend-team`, `frontend-team`, `data-engineering`
- ❌ Bad: `team1`, `MyTeam`, `developers`

### Security

**Versioning**:
- Always enable for production data
- Recommended for staging
- Optional for dev

**Encryption**:
- Use `AES256` for most use cases
- Use `aws:kms` only if compliance requires

**Public Access**:
- Default to `false` (private)
- Only enable for static website hosting
- Requires security approval for production

### Cost Optimization

**Lifecycle Policies**:
- Use `transition-to-glacier-30d` for archival data
- Use `expire-old-versions-90d` for versioned buckets
- Set to `none` for frequently accessed data

**Right-Sizing**:
- Request infrastructure only when needed
- Delete unused resources (submit deletion request)
- Monitor storage usage in AWS console

### Team Collaboration

**Resource Discovery**:
- Always search catalog before requesting new resources
- Check team filter to see existing infrastructure
- Reuse existing infrastructure when possible

**Documentation**:
- Use descriptive bucket purposes
- Fill in business justification for staging/prod
- Tag resources with team and cost center

**Communication**:
- Notify team when requesting shared infrastructure
- Document infrastructure usage in team wiki
- Report issues in `#platform-engineering` Slack channel

## Troubleshooting

### Request Failed - Validation Error

**Symptom**: Port.io run shows "Failed" with validation error

**Common Causes**:
- Invalid bucket name format
- Invalid purpose or team name format
- Missing required fields

**Solution**:
1. Read error message in Port.io run details
2. Correct invalid fields
3. Retry request with corrected information

### Request Stuck "In Progress"

**Symptom**: Port.io run shows "In Progress" for >30 minutes

**Possible Causes**:
- GitHub Actions runner queue full
- Manual approval pending (staging/prod)
- ArgoCD sync delayed
- Crossplane provisioning slow

**Solution**:
1. Check Port.io run for last successful step
2. If "PR created", check GitHub for approval status
3. If "ArgoCD syncing", check ArgoCD UI
4. If still stuck, contact platform team in Slack

### Bucket Not Appearing in Catalog

**Symptom**: Bucket provisioned but not visible in Port.io

**Possible Causes**:
- Port.io exporter sync delay (up to 5 minutes)
- Exporter filtering by label
- Blueprint mismatch

**Solution**:
1. Wait 5 minutes for sync
2. Check Crossplane resource exists: `kubectl get objectstorage -A`
3. Contact platform team if still not visible

### Cannot Access Provisioned Bucket

**Symptom**: Application cannot read/write to bucket

**Common Causes**:
- IAM permissions not configured
- Connection secret not mounted
- Incorrect bucket name in application

**Solution**:
1. Verify bucket name in Port.io matches application config
2. Check connection secret exists: `kubectl get secret -n NAMESPACE`
3. Verify IRSA configuration for application service account
4. Check CloudWatch logs for AWS access denied errors

## Support

**Platform Engineering Team**:
- Slack: `#platform-engineering`
- Email: platform-team@company.com
- On-Call: PagerDuty escalation

**Documentation**:
- [Setup Guide](01-setup-guide.md)
- [Troubleshooting](03-troubleshooting.md)
- [Architecture](04-architecture.md)

**Port.io Support**:
- Documentation: https://docs.getport.io/
- Support Email: support@getport.io

---
**Last Updated**: 2025-11-06
**Version**: 1.0
**Maintainer**: Platform Engineering Team
