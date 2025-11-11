# Port.io Setup Guide

This guide walks you through setting up Port.io for infrastructure self-service in Portal Kombat.

## Architecture Overview

```
Developer → Port UI → GitHub Workflow → Pull Request → ArgoCD → Crossplane → AWS
```

**Flow:**
1. Developer requests infrastructure through Port's self-service UI
2. Port triggers GitHub workflow with request parameters
3. Workflow creates infrastructure claim YAML files
4. Workflow opens a Pull Request for review
5. After PR merge, ArgoCD syncs the new claim
6. Crossplane provisions the AWS resources
7. Port catalog is updated with the new entity

## Prerequisites

- Port.io account (free tier available)
- GitHub repository access
- GitHub Actions enabled
- Kubernetes cluster with Crossplane and ArgoCD installed

## Step 1: Create Port Account and Workspace

1. Sign up at [https://app.getport.io/signup](https://app.getport.io/signup)
2. Create a new workspace: `portal-kombat`
3. Note your credentials:
   - **Client ID**: Found in Settings → Credentials
   - **Client Secret**: Generate in Settings → Credentials

## Step 2: Add GitHub Secrets

Add Port credentials to your GitHub repository:

```bash
# Navigate to GitHub repository
# Settings → Secrets and variables → Actions → New repository secret

PORT_CLIENT_ID=<your-client-id>
PORT_CLIENT_SECRET=<your-client-secret>
```

## Step 3: Install Port GitHub App

1. Go to [https://github.com/apps/port-io](https://github.com/apps/port-io)
2. Click **Install** or **Configure**
3. Select your organization and repository: `portal-kombat`
4. Grant permissions:
   - Read access to code
   - Read/write access to pull requests
   - Read access to workflows

## Step 4: Create Blueprints in Port

Blueprints define the data model for your infrastructure catalog.

### Import via Port UI

1. Navigate to **Builder** → **Blueprints**
2. Click **+ Blueprint** → **Edit JSON**
3. Import each blueprint from `port/blueprints/`:

**Import Order (important for relations):**

1. **XRD Blueprint**: `port/blueprints/xrd.json`
2. **Composition Blueprint**: `port/blueprints/composition.json`
3. **ArgoCD App Blueprint**: `port/blueprints/argocd-app.json`
4. **Infrastructure Claim Blueprint**: `port/blueprints/infrastructure-claim.json`

### Import via API (Alternative)

```bash
# Set your credentials
export PORT_CLIENT_ID="gWVcpoKHEkXO08XA9kkXzuIATv5POjij"
export PORT_CLIENT_SECRET="OntDC9LMg780GlKwZYZxIEknQMbZnYQ5nM7HX8wWfBG8TtvKRsy13xcZg8y8sILy"

# Get access token
ACCESS_TOKEN=$(curl -X POST https://api.us.port.io/v1/auth/access_token -H "Content-Type: application/json" -d "{\"clientId\":\"$PORT_CLIENT_ID\",\"clientSecret\":\"$PORT_CLIENT_SECRET\"}" | jq -r .accessToken)

# Import blueprints
for blueprint in port/blueprints/*.json; do
  echo "Importing $blueprint..."
  curl -X POST https://api.us.port.io/v1/blueprints \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @"$blueprint"
done
```

## Step 5: Populate Software Catalog

Load existing infrastructure into Port's catalog:

### Option A: Via Port GitHub Integration

1. In Port, go to **Data Sources** → **Git**
2. Click **+ Data Source** → **GitHub**
3. Configure:
   - **Repository**: `portal-kombat`
   - **File Pattern**: `**/port.yml` or `**/*-port.yml`
   - **Auto-sync**: Enable

Port will automatically discover and sync all `port.yml` files in your repository.

### Option B: Manual Entity Creation via API

```bash
# Import catalog entities
for catalog_file in port/catalog/*.yml; do
  echo "Importing entities from $catalog_file..."

  # Parse YAML and create entities
  yq eval -o=json '.' "$catalog_file" | jq -c '.[]' | while read entity; do
    BLUEPRINT=$(echo "$entity" | jq -r .blueprint)
    IDENTIFIER=$(echo "$entity" | jq -r .identifier)

    curl -X POST "https://api.us.port.io/v1/blueprints/$BLUEPRINT/entities" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$entity"
  done
done
```

## Step 6: Create Self-Service Actions

Self-service actions allow developers to request infrastructure through Port's UI.

### Import via Port UI

1. Navigate to **Self-Service** → **Actions**
2. Click **+ Action**
3. Select **Backend**: GitHub Workflow
4. Import actions from `port/actions/`:
   - `create-s3-bucket.json`
   - `create-transit-gateway.json`

**Update GitHub Configuration:**
- Replace `yourusername` with your GitHub username/org
- Replace `portal-kombat` with your repository name (if different)

### Import via API

```bash
# Import self-service actions
for action_file in port/actions/*.json; do
  echo "Importing action from $action_file..."

  # Update placeholders in action
  sed "s/ims-platform-dev/YOUR_GITHUB_USERNAME/g" "$action_file" | \
  curl -X POST https://api.us.port.io/v1/actions \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d @-
done
```

## Step 7: Test Self-Service Flow

### Test S3 Bucket Request

1. In Port UI, go to **Self-Service** tab
2. Click **Request S3 Bucket** action
3. Fill in the form:
   - **Bucket Name**: `portal-kombat-dev-test-12345`
   - **Environment**: `dev`
   - **Region**: `us-east-2`
   - **Versioning**: `true`
   - **Purpose**: `application-data`
4. Click **Execute**

**Expected Results:**
- Port shows run status: "Running"
- GitHub Actions workflow triggered
- New branch created: `port/s3-bucket-portal-kombat-dev-test-12345-<run-id>`
- Pull Request opened with infrastructure claim YAML
- Port run status updates: "Success"

### Review and Merge PR

1. Review the Pull Request in GitHub
2. Check the generated YAML files:
   - `environments/dev/infrastructure/storage/portal-kombat-dev-test-12345.yaml`
   - `environments/dev/infrastructure/storage/portal-kombat-dev-test-12345-port.yml`
3. Merge the PR

**GitOps Workflow:**
- ArgoCD detects change and syncs
- Crossplane reconciles the ObjectStorage claim
- AWS S3 bucket is provisioned
- Resource shows as "Ready" in kubectl

### Verify in Kubernetes

```bash
# Check claim status
kubectl get objectstorage portal-kombat-dev-test-12345

# Check AWS resource
kubectl get bucket -l crossplane.io/claim-name=portal-kombat-dev-test-12345

# View ArgoCD sync status
kubectl get application dev-infrastructure-claims -n argocd
```

### Update Port Entity (Manual - Optional)

After provisioning, update the Port entity with AWS resource ID:

```bash
# Get AWS bucket name
AWS_BUCKET=$(kubectl get bucket -l crossplane.io/claim-name=portal-kombat-dev-test-12345 -o jsonpath='{.items[0].status.atProvider.id}')

# Update Port entity
curl -X PATCH "https://api.getport.io/v1/blueprints/infrastructureClaim/entities/dev-portal-kombat-dev-test-12345" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "status": "ready",
      "awsResourceId": "'"$AWS_BUCKET"'"
    }
  }'
```

## Step 8: Advanced Configuration (Optional)

### Enable Auto-Sync from Kubernetes

Install Port's Kubernetes exporter to automatically sync Crossplane resource status:

```bash
# Add Port Helm repo
helm repo add port-labs https://port-labs.github.io/helm-charts
helm repo update

# Install exporter
helm install port-k8s-exporter port-labs/port-k8s-exporter \
  --create-namespace \
  --namespace port-k8s-exporter \
  --set secret.secrets.portClientId=$PORT_CLIENT_ID \
  --set secret.secrets.portClientSecret=$PORT_CLIENT_SECRET \
  --set-file configMap.config=port/k8s-exporter-config.yaml
```

Create the exporter configuration:

```yaml
# port/k8s-exporter-config.yaml
resources:
  - kind: v1/Bucket
    selector:
      query: .metadata.namespace | startswith("crossplane-system")
    port:
      entity:
        mappings:
          identifier: .metadata.labels."crossplane.io/claim-name"
          title: .metadata.name
          blueprint: '"infrastructureClaim"'
          properties:
            status: if .status.conditions[0].status == "True" then "ready" else "pending" end
            awsResourceId: .status.atProvider.id
            region: .spec.forProvider.region

  - kind: objectstorage.aws.platform.example/v1alpha1
    selector:
      query: .metadata.namespace
    port:
      entity:
        mappings:
          identifier: .metadata.name
          title: .metadata.name
          blueprint: '"infrastructureClaim"'
          properties:
            environment: .metadata.labels."portal-kombat.io/environment"
            claimType: '"objectstorage"'
            region: .spec.parameters.region
            status: if .status.conditions[0].status == "True" then "ready" else "pending" end
```

### Add Approval Workflow

For production environments, require approval before provisioning:

1. Edit action in Port UI: **Self-Service** → **Actions** → **Request S3 Bucket**
2. Enable **Require Approval**
3. Add approvers (users or teams)

### Create Scorecards for Infrastructure Quality

Define quality standards for infrastructure:

```bash
# Create scorecard via API
curl -X POST https://api.getport.io/v1/blueprints/infrastructureClaim/scorecards \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "infrastructure_quality",
    "title": "Infrastructure Quality",
    "levels": [
      {"title": "Basic", "color": "paleBlue"},
      {"title": "Bronze", "color": "bronze"},
      {"title": "Silver", "color": "silver"},
      {"title": "Gold", "color": "gold"}
    ],
    "rules": [
      {
        "identifier": "has_versioning",
        "title": "Has Versioning Enabled",
        "level": "Bronze",
        "query": {
          "combinator": "and",
          "conditions": [
            {
              "property": "claimType",
              "operator": "=",
              "value": "objectstorage"
            },
            {
              "property": "tags.versioning",
              "operator": "=",
              "value": true
            }
          ]
        }
      },
      {
        "identifier": "has_encryption",
        "title": "Has Encryption Enabled",
        "level": "Silver",
        "query": {
          "combinator": "and",
          "conditions": [
            {
              "property": "claimType",
              "operator": "=",
              "value": "objectstorage"
            },
            {
              "property": "tags.encryption",
              "operator": "=",
              "value": true
            }
          ]
        }
      },
      {
        "identifier": "in_production",
        "title": "Production Environment",
        "level": "Gold",
        "query": {
          "property": "environment",
          "operator": "=",
          "value": "prod"
        }
      }
    ]
  }'
```

## Troubleshooting

### GitHub Workflow Not Triggering

**Issue**: Port action executes but GitHub workflow doesn't run.

**Solutions:**
1. Verify Port GitHub App is installed: [https://github.com/apps/port-io](https://github.com/apps/port-io)
2. Check workflow file exists: `.github/workflows/port-create-s3-bucket.yml`
3. Verify workflow permissions: Settings → Actions → General → Workflow permissions
4. Check Port action configuration has correct org/repo

### Port Entity Not Created

**Issue**: PR merged but entity doesn't appear in Port catalog.

**Solutions:**
1. Check Port GitHub integration: **Data Sources** → **Git**
2. Verify `port.yml` file format (valid YAML)
3. Manually trigger resync: **Data Sources** → **Git** → **Resync**
4. Check blueprint identifier matches

### Crossplane Resource Not Ready

**Issue**: Kubernetes claim created but AWS resource not provisioned.

**Solutions:**
1. Check Crossplane provider status: `kubectl get providers`
2. Check provider logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3`
3. Verify IAM permissions (IRSA role)
4. Check claim status: `kubectl describe objectstorage <name>`

### Port Run Shows "Failed"

**Issue**: Port action run fails with error.

**Solutions:**
1. Check GitHub Actions logs: Actions tab → Workflow run
2. Common issues:
   - Missing GitHub secrets (PORT_CLIENT_ID, PORT_CLIENT_SECRET)
   - Invalid bucket name (must be globally unique)
   - Branch already exists (run ID collision)
3. Fix issue and re-run action

## Next Steps

1. **Add More Actions**: Create actions for Transit Gateway Attachments, Route Tables, RDS databases
2. **Create Dashboards**: Build custom views in Port for infrastructure visibility
3. **Set Up Cost Tracking**: Integrate AWS Cost Explorer data into Port entities
4. **Enable Notifications**: Configure Slack/Teams notifications for action runs
5. **Implement RBAC**: Use Port teams and permissions for access control

## Resources

- [Port Documentation](https://docs.getport.io/)
- [Port GitHub App](https://github.com/apps/port-io)
- [Port API Reference](https://docs.getport.io/api-reference/)
- [Port Actions Guide](https://docs.getport.io/actions-and-automations/)
- [Crossplane Documentation](https://docs.crossplane.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
