# Port.io GitHub App Configuration Guide

This guide walks you through setting up Port.io's GitHub integration to trigger GitHub Actions workflows for infrastructure provisioning.

## Prerequisites

- Port.io account (US instance): https://app.us.getport.io
- GitHub organization: `ims-platform-dev`
- Repository: `portal-kombat`
- Admin access to both Port.io and GitHub organization

## Overview

Port.io uses a GitHub App to:
1. Trigger `workflow_dispatch` events in your repository
2. Report workflow run status back to Port.io
3. Enable self-service actions to create PRs automatically

## Step-by-Step Configuration

### Step 1: Access Port.io Settings

1. Navigate to **Port.io web UI**: https://app.us.getport.io
2. Log in with your credentials
3. Click on your **profile icon** (top-right corner)
4. Select **Settings** or click the gear icon ⚙️

### Step 2: Navigate to GitHub Integration

1. In the Settings page, look for the left sidebar
2. Click on **Integrations** or **Git Providers**
3. Find **GitHub** in the list of available integrations
4. Click **Connect** or **Install** next to GitHub

### Step 3: Install Port.io GitHub App

You'll be redirected to GitHub to authorize the Port.io app.

**On GitHub authorization page:**

1. **Select organization**: Choose `ims-platform-dev` from the dropdown
2. **Repository access**: Select one of these options:
   - ✅ **Only select repositories** (Recommended)
     - Search for and select: `portal-kombat`
   - ⚠️ All repositories (not recommended for security)

3. **Permissions**: Port.io will request these permissions:
   ```
   Repository permissions:
   - Actions: Read and write ✅ (Required - to trigger workflow_dispatch)
   - Contents: Read ✅ (Required - to read repository structure)
   - Pull requests: Read and write ✅ (Required - workflows create PRs)
   - Metadata: Read ✅ (Automatically included)

   Organization permissions:
   - Members: Read (Optional - for user mapping)
   ```

4. Click **Install** or **Authorize** button (green button)

5. You'll be redirected back to Port.io

### Step 4: Verify GitHub Integration in Port.io

Back in Port.io:

1. You should see **GitHub** marked as ✅ **Connected**
2. It should show:
   - Organization: `ims-platform-dev`
   - Repository: `portal-kombat`
   - Status: Active

### Step 5: Configure Self-Service Action Backend

Now we need to tell Port.io which action should use GitHub.

**Option A: Via Port.io UI (Recommended)**

1. In Port.io, go to **Builder** (left sidebar)
2. Click on **Self-service** or **Actions**
3. Find the blueprint: **s3-bucket** (or create action if it doesn't exist)
4. Click **+ New Action** or edit existing action

**Action Configuration:**

```yaml
Identifier: provision_s3_bucket
Title: Provision S3 Bucket
Description: Request a new S3 bucket for application use
Icon: Bucket

Backend Configuration:
  Type: GitHub
  Organization: ims-platform-dev
  Repository: portal-kombat
  Workflow File: port-s3-provisioning.yaml

Advanced Options:
  ✅ Report workflow status to Port.io
  ✅ Include action payload in workflow
  ✅ Include user inputs in workflow
```

**Option B: Via Port.io API (Alternative)**

If the UI doesn't have the action yet, create it via API:

```bash
# Get Port.io token
PORT_TOKEN=$(curl -s -X POST https://api.us.getport.io/v1/auth/access_token \
  -H "Content-Type: application/json" \
  -d '{"clientId":"gWVcpoKHEkXO08XA9kkXzuIATv5POjij","clientSecret":"<YOUR_SECRET>"}' \
  | jq -r '.accessToken')

# Create action
curl -X POST "https://api.us.getport.io/v1/blueprints/s3-bucket/actions" \
  -H "Authorization: Bearer $PORT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @config/port-io/actions/provision-s3-bucket.json
```

### Step 6: Test the Integration

**Test 1: Verify GitHub App Permissions**

1. Go to GitHub: https://github.com/organizations/ims-platform-dev/settings/installations
2. Find **Port** in the installed GitHub Apps
3. Click **Configure**
4. Verify it has access to `portal-kombat` repository
5. Verify permissions are correct

**Test 2: Trigger Test Workflow from Port.io**

1. In Port.io, go to **Catalog** (left sidebar)
2. You should see the **S3 Buckets** entity type (may be empty)
3. Click **+ Create** or **Actions** → **Provision S3 Bucket**
4. Fill in the form:
   ```
   Bucket Purpose: test-bucket
   Environment: dev
   Team Name: platform-engineering
   Enable Versioning: No
   Encryption Type: AES256
   Lifecycle Policy: none
   Public Read Access: No (unchecked)
   Cost Center: engineering
   Business Justification: Testing Port.io GitHub integration
   ```
5. Click **Execute** or **Create**

**Expected Results:**

1. Port.io shows action status as "Running"
2. GitHub Actions workflow is triggered
3. After ~1-2 minutes:
   - Workflow creates a PR in your repository
   - PR contains Crossplane ObjectStorage YAML
   - PR is auto-merged (dev environment)
   - ArgoCD syncs the change
   - Crossplane provisions S3 bucket in AWS
4. After ~3-5 minutes:
   - Port.io exporter syncs bucket back to catalog
   - Bucket appears in Port.io Catalog

### Step 7: Monitor and Debug

**View Workflow Run in GitHub:**

```bash
# Using GitHub CLI
gh run list --workflow=port-s3-provisioning.yaml
gh run view --log  # View latest run logs
```

**Or in browser:**
- https://github.com/ims-platform-dev/portal-kombat/actions/workflows/port-s3-provisioning.yaml

**View Port.io Logs:**

1. In Port.io, go to **Runs** (left sidebar)
2. Find your action run
3. Click to see details and logs
4. Check status: TRIGGERED → RUNNING → SUCCESS/FAILURE

**Check Port.io Exporter:**

```bash
# Check exporter is running
kubectl get pods -n port-exporter
kubectl logs -n port-exporter -l app.kubernetes.io/name=port-k8s-exporter --tail=50

# Check for ObjectStorage resources
kubectl get objectstorage -n dev
```

## Common Issues and Solutions

### Issue 1: "GitHub App not authorized"

**Symptoms**: Action fails with "unauthorized" error

**Solution**:
1. Go to GitHub: https://github.com/settings/installations
2. Find Port.io app
3. Click Configure
4. Verify repository access and permissions
5. Re-authorize if needed

### Issue 2: "Workflow not found"

**Symptoms**: Port.io says "workflow file not found"

**Solution**:
1. Verify workflow file exists: `.github/workflows/port-s3-provisioning.yaml`
2. Verify workflow filename is correct in Port.io action config
3. Push workflow file to main branch if missing

### Issue 3: "Workflow triggered but fails"

**Symptoms**: Workflow starts but fails at some step

**Solution**:
```bash
# Check workflow logs
gh run list --workflow=port-s3-provisioning.yaml
gh run view --log

# Common causes:
# - Missing secrets (PORT_CLIENT_ID, PORT_CLIENT_SECRET)
# - Invalid payload structure
# - kubectl not configured on runner
# - Git credentials not configured
```

### Issue 4: "Port.io doesn't show run status"

**Symptoms**: Workflow completes but Port.io doesn't update

**Solution**:
1. Verify "Report workflow status" is enabled in action config
2. Check workflow logs for Port.io API call
3. Verify API endpoint is `api.us.getport.io` (not EU endpoint)
4. Verify secrets are configured: `PORT_CLIENT_ID`, `PORT_CLIENT_SECRET`

### Issue 5: "Port.io exporter not syncing resources"

**Symptoms**: S3 bucket created but not appearing in Port.io catalog

**Solution**:
```bash
# Check exporter logs
kubectl logs -n port-exporter -l app.kubernetes.io/name=port-k8s-exporter --tail=100

# Verify ObjectStorage resource exists
kubectl get objectstorage -n dev

# Verify blueprint exists in Port.io
curl -X GET https://api.us.getport.io/v1/blueprints/s3-bucket \
  -H "Authorization: Bearer <TOKEN>" | jq .
```

## GitHub Secrets Configuration

The workflow needs these secrets configured in GitHub:

```bash
# Navigate to repository settings
# https://github.com/ims-platform-dev/portal-kombat/settings/secrets/actions

# Add these secrets:
PORT_CLIENT_ID=gWVcpoKHEkXO08XA9kkXzuIATv5POjij
PORT_CLIENT_SECRET=<your-secret-here>

# Optional (if using self-hosted runners):
KUBE_CONFIG=<base64-encoded-kubeconfig>
```

**To add secrets via GitHub CLI:**

```bash
# Set Port.io secrets
gh secret set PORT_CLIENT_ID --body "gWVcpoKHEkXO08XA9kkXzuIATv5POjij"
gh secret set PORT_CLIENT_SECRET --body "<your-secret>"

# Verify secrets are set
gh secret list
```

## Verification Checklist

- [ ] Port.io GitHub App installed to `ims-platform-dev/portal-kombat`
- [ ] GitHub App has correct permissions (actions: write, contents: read, pull_requests: write)
- [ ] Port.io shows GitHub integration as "Connected"
- [ ] Self-service action configured with GitHub backend
- [ ] GitHub secrets configured (PORT_CLIENT_ID, PORT_CLIENT_SECRET)
- [ ] Test workflow triggered successfully from Port.io
- [ ] Workflow creates PR with Crossplane YAML
- [ ] PR auto-merged in dev environment
- [ ] Crossplane provisions S3 bucket in AWS
- [ ] Port.io exporter syncs bucket to catalog

## Next Steps

Once GitHub App is configured:

1. **Test with real bucket**: Create a production-like S3 bucket request
2. **Test staging environment**: Try provisioning with manual approval
3. **Onboard developers**: Share Port.io catalog URL with team
4. **Monitor integration**: Set up alerts for workflow failures

## Resources

- **Port.io GitHub Backend Docs**: https://docs.getport.io/actions-and-automations/setup-backend/github-backend
- **Port.io Actions Guide**: https://docs.getport.io/actions-and-automations/
- **GitHub Apps Documentation**: https://docs.github.com/en/apps
- **Repository**: https://github.com/ims-platform-dev/portal-kombat
- **Port.io Instance**: https://app.us.getport.io
