# Port Self-Service: Developer Guide

A practical guide for developers to request infrastructure through Port's self-service portal.

## Quick Start

### Access Port

1. Navigate to [https://app.getport.io](https://app.getport.io)
2. Log in with your organization credentials
3. Select the **portal-kombat** workspace

### Request Infrastructure

Click the **Self-Service** tab to see available infrastructure actions.

## Available Infrastructure Types

### 1. S3 Bucket

**Use Cases:**
- Application file storage
- User uploads
- Static website hosting
- Backup storage
- Log aggregation
- Terraform state backend

**How to Request:**

1. Click **Request S3 Bucket** in Self-Service tab
2. Fill in the form:

| Field | Description | Example |
|-------|-------------|---------|
| Bucket Name | Globally unique name (must start with `portal-kombat-`) | `portal-kombat-dev-myapp-uploads-78901` |
| Environment | Target environment | `dev`, `staging`, or `prod` |
| Region | AWS region | `us-east-2` (default) |
| Versioning | Keep object history | `true` (recommended) |
| Encryption | Server-side encryption | `true` (mandatory for prod) |
| Purpose | What is this bucket for? | `user-uploads` |

3. Click **Execute**

**What Happens Next:**

- ⏳ GitHub workflow creates infrastructure files
- 📋 Pull Request opened for review
- 👀 Platform team reviews and merges PR
- 🚀 ArgoCD syncs changes automatically
- ☁️ Crossplane provisions S3 bucket in AWS
- ✅ You receive notification when ready

**Timeline:** ~5-10 minutes after PR merge

**Accessing Your Bucket:**

```bash
# Get bucket details
kubectl get objectstorage portal-kombat-dev-myapp-uploads-78901

# Get AWS bucket name
kubectl get bucket -l crossplane.io/claim-name=portal-kombat-dev-myapp-uploads-78901 -o jsonpath='{.status.atProvider.id}'
```

### 2. Transit Gateway

**Use Cases:**
- Hub-and-spoke network topology
- VPC interconnection
- Centralized shared services
- Multi-region connectivity

**How to Request:**

1. Click **Request Transit Gateway** in Self-Service tab
2. Fill in the form:

| Field | Description | Example |
|-------|-------------|---------|
| Transit Gateway Name | Descriptive name | `hub-tgw`, `prod-main-tgw` |
| Environment | Target environment | `dev`, `staging`, or `prod` |
| Region | AWS region | `us-east-2` |
| Amazon Side ASN | BGP ASN for TGW | `64512` (default) |
| DNS Support | Enable DNS resolution | `true` (recommended) |
| VPN ECMP Support | Multi-path VPN routing | `true` (recommended) |
| Purpose | Primary use case | `hub-spoke` |

3. Click **Execute**

**What Happens Next:**

Same GitOps workflow as S3 buckets (PR → Merge → ArgoCD → Crossplane → AWS)

**Timeline:** ~10-15 minutes after PR merge

**Next Steps After Provisioning:**

1. Attach VPCs using **TransitGatewayAttachment**
2. Create route tables with **TransitGatewayRouteTable**
3. Configure route propagations for dynamic routing

## Understanding the GitOps Workflow

### The Flow

```
You → Port UI → GitHub Workflow → Pull Request → Code Review → Merge → ArgoCD → Crossplane → AWS
```

### Why Pull Requests?

**Benefits:**
- **Review**: Platform team can validate configurations
- **Audit**: Track who requested what and when
- **Rollback**: Easy to revert if issues arise
- **Compliance**: Meets change management requirements
- **Learning**: See what gets created under the hood

### PR Review Process

**For Dev Environment:**
- Auto-merge enabled (no approval required)
- Changes applied within minutes

**For Staging/Prod Environments:**
- Manual approval required from platform team
- Security and compliance checks
- Cost estimation review
- Timeline: 1-2 business days

## Tracking Your Request

### In Port

1. Go to **Self-Service** → **Runs**
2. Find your action run
3. View status:
   - 🔵 **Running**: GitHub workflow in progress
   - ✅ **Success**: PR created successfully
   - ❌ **Failed**: Check logs for errors

4. Click run to see:
   - Pull Request URL
   - Workflow logs
   - Status updates

### In GitHub

1. Navigate to [portal-kombat repository](https://github.com/yourusername/portal-kombat)
2. Check **Pull Requests** tab
3. Find PR with `[Port]` prefix
4. View files that will be created

### In Kubernetes (After Merge)

```bash
# Check ArgoCD sync status
kubectl get application dev-infrastructure-claims -n argocd

# Check your infrastructure claim
kubectl get objectstorage
kubectl get transitgateway

# View detailed status
kubectl describe objectstorage <your-resource-name>

# Check if AWS resource is ready
kubectl get managed | grep <your-resource-name>
```

### In Port Catalog

1. Go to **Catalog** → **Infrastructure Claims**
2. Find your resource by name
3. View:
   - Status (pending → ready)
   - AWS Resource ID
   - Related ArgoCD app
   - Git file path
   - Creation date and creator

## Common Scenarios

### Scenario 1: My Application Needs File Storage

**Goal**: Store user-uploaded files

**Steps:**
1. Request S3 bucket via Port
   - Name: `portal-kombat-dev-myapp-uploads-12345`
   - Purpose: `user-uploads`
   - Versioning: `true`
   - Encryption: `true`

2. Wait for PR merge and provisioning

3. Get bucket credentials:
```bash
# Your application will use IRSA (IAM Roles for Service Accounts)
# No access keys needed!

# Get bucket name
BUCKET_NAME=$(kubectl get bucket -l crossplane.io/claim-name=portal-kombat-dev-myapp-uploads-12345 -o jsonpath='{.status.atProvider.id}')

# Configure your app (example: Node.js)
AWS_REGION=us-east-2
S3_BUCKET=$BUCKET_NAME
```

4. Deploy your application with IRSA role that has S3 access

### Scenario 2: Connecting Multiple VPCs

**Goal**: Connect app VPC to shared services VPC

**Prerequisites:**
- Transit Gateway already provisioned
- VPCs already exist

**Steps:**
1. Request Transit Gateway (if not exists)
2. Request Transit Gateway Attachment for App VPC
3. Request Transit Gateway Attachment for Shared Services VPC
4. Request Transit Gateway Route Table with propagations
5. Test connectivity between VPCs

### Scenario 3: Setting Up Dev Environment

**Goal**: New developer needs complete dev infrastructure

**Steps:**

1. **Storage**: Request S3 bucket for application data
   - Purpose: `application-data`

2. **Networking**: Verify Transit Gateway exists
   - If not, request Transit Gateway

3. **Compute**: Request EKS cluster (coming soon)

4. **Monitoring**: Use existing cluster add-ons (already deployed)

## Best Practices

### Naming Conventions

**S3 Buckets:**
```
portal-kombat-{env}-{app}-{purpose}-{random}

Examples:
✅ portal-kombat-dev-myapp-uploads-12345
✅ portal-kombat-prod-api-backups-67890
❌ my-bucket (doesn't follow convention)
❌ portal-kombat-bucket (not descriptive enough)
```

**Transit Gateways:**
```
{purpose}-tgw

Examples:
✅ hub-tgw
✅ prod-main-tgw
✅ shared-services-tgw
❌ tgw1 (not descriptive)
❌ my_tgw (use hyphens, not underscores)
```

### Resource Tagging

All resources are automatically tagged with:
- `Environment`: dev/staging/prod
- `ManagedBy`: Port
- `Project`: portal-kombat
- `CreatedBy`: port-self-service
- `Purpose`: Your specified purpose

### Cost Considerations

**Free Tier / Low Cost:**
- S3 buckets: ~$0.023/GB/month
- Transit Gateway idle: ~$36/month

**Be Mindful:**
- S3 versioning increases storage costs
- Transit Gateway data transfer charges
- Unused resources should be deleted

**Cost Optimization:**
- Use dev environment for testing
- Delete resources when no longer needed
- Request staging/prod only when necessary

### Security

**Automatic Security Features:**
- S3 buckets: Public access blocked by default
- S3 buckets: Encryption enabled
- Transit Gateways: Private networking only
- All resources: Tagged for compliance

**Your Responsibilities:**
- Choose appropriate environments
- Don't store secrets in bucket names
- Use IRSA instead of access keys
- Follow principle of least privilege

## Troubleshooting

### Port Action Failed

**Symptoms**: Run shows "Failed" status in Port

**Solutions:**
1. Check error message in Port run logs
2. Common issues:
   - Bucket name not unique (add more random digits)
   - Invalid characters in names
   - Region not supported
3. Fix issue and **re-run action** (no need to start over)

### Pull Request Not Created

**Symptoms**: Action succeeds but no PR appears

**Solutions:**
1. Check GitHub Actions tab for workflow runs
2. Verify you have correct repository permissions
3. Contact platform team if issue persists

### Resource Shows as "Pending"

**Symptoms**: PR merged but resource not ready

**Normal Behavior:**
- Allow 5-10 minutes for provisioning
- ArgoCD syncs every 3 minutes
- Crossplane reconciles every 1 minute

**If Still Pending After 15 Minutes:**
```bash
# Check ArgoCD app health
kubectl get application dev-infrastructure-claims -n argocd

# Check infrastructure claim status
kubectl describe objectstorage <your-resource-name>

# Check for events
kubectl get events --sort-by='.lastTimestamp' | grep <your-resource-name>
```

**Contact platform team if:**
- Status shows error condition
- Events indicate permission issues
- Resource stuck in "Creating" state

### Can't Find My Resource

**Symptoms**: Created resource not visible

**Check These Locations:**

1. **Port Catalog**: Catalog → Infrastructure Claims
2. **GitHub**: Pull Requests (merged)
3. **Kubernetes**:
```bash
kubectl get objectstorage
kubectl get transitgateway
```

4. **AWS Console**:
   - S3: Services → S3
   - Transit Gateway: VPC → Transit Gateways

### How Do I Delete Infrastructure?

**Process:**

1. Create Pull Request manually to remove YAML files:
```bash
git checkout -b remove-myapp-bucket
rm environments/dev/infrastructure/storage/portal-kombat-dev-myapp-bucket-12345.yaml
rm environments/dev/infrastructure/storage/portal-kombat-dev-myapp-bucket-12345-port.yml
git commit -m "Remove S3 bucket for myapp"
git push
# Create PR
```

2. After PR merge:
   - ArgoCD syncs
   - Crossplane deletes AWS resource
   - Port entity removed

**Important**: Deletion is permanent and cannot be undone!

## Getting Help

### Documentation

- **Port Setup**: `docs/PORT_SETUP.md`
- **Routing Guide**: `docs/ROUTING_COMPOSITION.md`
- **CLAUDE.md**: Platform architecture and commands

### Support Channels

1. **Platform Team**: #platform-team (Slack)
2. **GitHub Issues**: Open issue in portal-kombat repo
3. **Port Support**: help@getport.io

### Useful Links

- Port Catalog: [https://app.getport.io/infrastructureClaim](https://app.getport.io)
- GitHub Repo: [https://github.com/yourusername/portal-kombat](https://github.com/yourusername/portal-kombat)
- AWS Console: [https://console.aws.amazon.com](https://console.aws.amazon.com)

## FAQ

**Q: How long does it take to get infrastructure?**
A: Dev environment: ~5-10 minutes. Staging/Prod: 1-2 business days (requires approval).

**Q: Can I request infrastructure outside business hours?**
A: Yes! Port is available 24/7. Your request will be processed automatically for dev, or reviewed next business day for prod.

**Q: What if I make a mistake in my request?**
A: Close the PR before merge and re-run the action with correct parameters.

**Q: Can I request multiple resources at once?**
A: Currently, run one action per resource. Future enhancement: bulk requests.

**Q: How much does this cost?**
A: Port is free tier. AWS costs depend on usage. Typical dev resources: <$50/month.

**Q: Who can see my infrastructure requests?**
A: All requests are visible to your team in Port. GitHub PRs follow repository permissions.

**Q: Can I customize the infrastructure configuration?**
A: For custom requirements, edit the PR files before merge or contact platform team.

**Q: What environments are available?**
A: dev (auto-approve), staging (requires approval), prod (requires approval + security review).
