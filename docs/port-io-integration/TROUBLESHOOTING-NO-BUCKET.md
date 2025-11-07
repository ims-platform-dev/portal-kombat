# Troubleshooting: "Created test bucket but not seeing it"

## Quick Diagnostic Checklist

Run through these checks to identify where the flow broke:

### ✅ Step 1: Verify Port.io Action Was Triggered

**Check in Port.io UI:**
1. Go to https://app.us.getport.io
2. Navigate to **Runs** (left sidebar)
3. Look for your recent action run
4. Check the status:
   - ❌ **TRIGGERED** (stuck) = GitHub App not configured correctly
   - ❌ **FAILED** = Check error message
   - ✅ **RUNNING** or **SUCCESS** = Action triggered correctly

**Expected**: You should see a run with your test bucket request

### ✅ Step 2: Verify GitHub Workflow Was Triggered

**Check in GitHub:**
```bash
# Option A: Using browser
# Navigate to: https://github.com/ims-platform-dev/portal-kombat/actions

# Option B: Using GitHub CLI (if installed)
gh auth login  # If not already authenticated
gh run list --limit 10
```

**Expected**: You should see a workflow run named "Port.io S3 Bucket Provisioning"

**If no workflow run**:
- ❌ Port.io couldn't trigger the workflow
- Check: GitHub App permissions
- Check: Port.io action configuration

### ✅ Step 3: Check GitHub Secrets

The workflow needs Port.io credentials as GitHub secrets.

**Verify secrets exist:**
```bash
# Option A: Using GitHub CLI
gh secret list

# Option B: Via browser
# https://github.com/ims-platform-dev/portal-kombat/settings/secrets/actions
```

**Expected secrets:**
- `PORT_CLIENT_ID` = `gWVcpoKHEkXO08XA9kkXzuIATv5POjif`
- `PORT_CLIENT_SECRET` = (your secret value)

**If secrets missing, add them:**
```bash
gh secret set PORT_CLIENT_ID --body "gWVcpoKHEkXO08XA9kkXzuIATv5POjij"
gh secret set PORT_CLIENT_SECRET --body "<YOUR_SECRET>"
```

### ✅ Step 4: Check Port.io Action Configuration

**Verify in Port.io UI:**
1. Go to **Builder** → **Self-service** → **Actions**
2. Find action on `s3-bucket` blueprint
3. Check configuration:
   ```
   Backend Type: GitHub ✓
   Organization: ims-platform-dev ✓
   Repository: portal-kombat ✓
   Workflow File: port-s3-provisioning.yaml ✓
   ```

**Common mistakes:**
- ❌ Workflow filename wrong (must be exact: `port-s3-provisioning.yaml`)
- ❌ Wrong organization or repository name
- ❌ Backend type not set to "GitHub"

### ✅ Step 5: Check GitHub App Permissions

**Verify in GitHub:**
1. Go to: https://github.com/organizations/ims-platform-dev/settings/installations
2. Find **Port** app
3. Click **Configure**
4. Verify:
   - ✅ Repository access includes `portal-kombat`
   - ✅ Permissions include:
     - Actions: **Read and write**
     - Contents: **Read**
     - Pull requests: **Read and write**

**If permissions missing:**
1. Click **Configure** next to Port app
2. Update permissions
3. Save changes
4. Try creating bucket again in Port.io

### ✅ Step 6: Check Workflow File Exists

**Verify workflow file on main branch:**
```bash
# Check if file exists on main branch
git ls-remote --heads origin | grep main
curl -s https://raw.githubusercontent.com/ims-platform-dev/portal-kombat/main/.github/workflows/port-s3-provisioning.yaml | head -10
```

**Expected**: Workflow file should exist and start with:
```yaml
name: Port.io S3 Bucket Provisioning

on:
  workflow_dispatch:
```

**If file missing:**
- The workflow hasn't been pushed to main branch yet
- You need to push your local commits

## Common Scenarios

### Scenario 1: Port.io Run Shows "TRIGGERED" (Stuck)

**Symptoms:**
- Port.io shows action as "TRIGGERED"
- No GitHub workflow run appears
- Status doesn't change

**Cause**: Port.io can't trigger GitHub workflow

**Solutions:**
1. **Check GitHub App installation:**
   - Go to https://github.com/settings/installations
   - Find Port app
   - Verify it has access to `ims-platform-dev/portal-kombat`
   - Verify permissions: Actions (write), Contents (read), PRs (write)

2. **Re-install GitHub App:**
   - In Port.io: Settings → Integrations → GitHub
   - Click "Disconnect" then "Connect" again
   - Re-authorize with correct permissions

3. **Check workflow filename:**
   - Port.io action config must exactly match: `port-s3-provisioning.yaml`
   - No typos, no extra spaces

### Scenario 2: Workflow Runs But Fails

**Symptoms:**
- GitHub workflow triggered
- Workflow fails at some step
- Port.io shows "FAILED"

**Check workflow logs:**
```bash
gh run list --workflow=port-s3-provisioning.yaml
gh run view --log  # View latest run
```

**Common failures:**

**A. "Extract payload" step fails:**
```
Error: jq: error parsing JSON
```
**Solution**: Port.io payload structure incorrect
- Check Port.io action has "Include action payload" enabled
- Verify payload matches expected structure

**B. "Kubectl dry-run validation" step fails:**
```
Error: error: unable to recognize "STDIN": no matches for kind "ObjectStorage"
```
**Solution**: Crossplane XRD not installed
```bash
kubectl get xrd objectstorages.aws.platform.example
# If not found, install Crossplane platform XRDs
```

**C. "Update Port.io run status" step fails:**
```
Error: 401 Unauthorized
```
**Solution**: GitHub secrets not configured or wrong values
```bash
gh secret set PORT_CLIENT_ID --body "gWVcpoKHEkXO08XA9kkXzuIATv5POjij"
gh secret set PORT_CLIENT_SECRET --body "<YOUR_SECRET>"
```

### Scenario 3: Workflow Succeeds But No Bucket in Port.io

**Symptoms:**
- GitHub workflow completes successfully
- PR created and merged
- Crossplane resource created
- But bucket doesn't appear in Port.io catalog

**Check Port.io exporter:**
```bash
# Check exporter is running
kubectl get pods -n port-exporter
kubectl logs -n port-exporter -l app.kubernetes.io/name=port-k8s-exporter --tail=100

# Check ObjectStorage resources exist
kubectl get objectstorage -A

# Check resource in specific namespace
kubectl get objectstorage -n dev
kubectl describe objectstorage <name> -n dev
```

**Possible causes:**

**A. Exporter not configured to watch ObjectStorage:**
- Check ConfigMap: `kubectl get configmap -n port-exporter dev-port-exporter-port-k8s-exporter -o yaml`
- Should have resource configuration for `kind: ObjectStorage`

**B. Exporter authentication failing:**
- Check logs for auth errors
- Verify API endpoint is `https://api.us.getport.io`
- Verify credentials are correct

**C. Blueprint mismatch:**
- Exporter syncs to blueprint `s3-bucket`
- Verify blueprint exists: https://app.us.getport.io/settings/data-model
- Blueprint identifier must be exactly: `s3-bucket`

### Scenario 4: Workflow Succeeds But No AWS Bucket

**Symptoms:**
- Workflow completes
- Crossplane resource created
- But no actual S3 bucket in AWS

**Check Crossplane:**
```bash
# Check ObjectStorage status
kubectl get objectstorage -n dev
kubectl describe objectstorage <name> -n dev

# Check for Crossplane events
kubectl get events -n dev --sort-by='.lastTimestamp' | grep -i objectstorage

# Check Crossplane managed resources
kubectl get managed | grep -i bucket

# Check provider status
kubectl get providers
```

**Common Crossplane issues:**

**A. Provider not healthy:**
```bash
kubectl describe provider provider-aws-s3
# Check status and events
```

**B. IAM permissions missing:**
```bash
# Check provider config
kubectl get providerconfig -o yaml
# Verify IRSA configuration
kubectl describe sa -n crossplane-system | grep Annotations
```

**C. Composition not found:**
```bash
kubectl get compositions
# Should see composition for ObjectStorage
```

## Debug Commands Reference

```bash
# === Port.io Exporter ===
kubectl get pods -n port-exporter
kubectl logs -n port-exporter -l app.kubernetes.io/name=port-k8s-exporter --tail=100
kubectl describe pod -n port-exporter <pod-name>

# === GitHub Workflows ===
gh run list --limit 10
gh run view <run-id> --log
gh workflow list

# === Crossplane Resources ===
kubectl get objectstorage -A
kubectl describe objectstorage <name> -n <namespace>
kubectl get managed | grep -i bucket
kubectl get providers
kubectl get xrd

# === Kubernetes Events ===
kubectl get events -n dev --sort-by='.lastTimestamp' | tail -20
kubectl get events -n crossplane-system --sort-by='.lastTimestamp' | tail -20

# === Port.io API ===
# Get token
PORT_TOKEN=$(curl -s -X POST https://api.us.getport.io/v1/auth/access_token \
  -H "Content-Type: application/json" \
  -d '{"clientId":"gWVcpoKHEkXO08XA9kkXzuIATv5POjij","clientSecret":"<SECRET>"}' \
  | jq -r '.accessToken')

# List entities in catalog
curl -s -X GET "https://api.us.getport.io/v1/blueprints/s3-bucket/entities" \
  -H "Authorization: Bearer $PORT_TOKEN" | jq '.entities[] | .identifier'

# List action runs
curl -s -X GET "https://api.us.getport.io/v1/actions/runs?blueprint=s3-bucket" \
  -H "Authorization: Bearer $PORT_TOKEN" | jq '.runs[] | {id: .id, status: .status, createdAt: .createdAt}'
```

## Quick Fix: Test Manually

If Port.io integration isn't working, you can test the workflow manually:

```bash
# Run test script (simulates Port.io payload)
./scripts/test-port-workflow.sh

# Or trigger directly with gh CLI
gh workflow run port-s3-provisioning.yaml \
  --field port_payload='{
    "payload": {
      "properties": {
        "purpose": "manual-test",
        "environment": "dev",
        "team": "platform",
        "bucketName": "portal-kombat-dev-manual-test-12345",
        "versioning": false,
        "encryption": "AES256"
      }
    },
    "trigger": {"by": {"user": {"email": "manual@test.com"}}},
    "context": {"runId": "manual-test-123"}
  }'
```

## Still Not Working?

If you've checked all the above and it's still not working:

1. **Share Port.io run details:**
   - Screenshot of run status from Port.io UI
   - Run ID from Port.io

2. **Share GitHub workflow logs:**
   ```bash
   gh run list --limit 5
   gh run view <run-id> --log > workflow-logs.txt
   ```

3. **Share Crossplane status:**
   ```bash
   kubectl get objectstorage -A
   kubectl get providers
   kubectl get xrd | grep -i objectstorage
   ```

4. **Check the deployment status doc:**
   - `docs/port-io-integration/DEPLOYMENT-STATUS.md`
   - Verify all "Completed Steps" are actually complete
