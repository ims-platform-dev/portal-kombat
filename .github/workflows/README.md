# GitHub Workflows for Port Self-Service

This directory contains GitHub Actions workflows that are triggered by Port self-service actions.

## Workflows

### port-create-s3-bucket.yml

Creates an S3 bucket infrastructure claim through GitOps.

**Trigger:** Port Self-Service Action
**Port Action Config:** `port/actions/create-s3-bucket.json`

#### How It Works

1. **Port** triggers the workflow via GitHub Actions webhook
2. **Workflow** receives Port context with user inputs
3. **Parses** the Port context to extract bucket configuration
4. **Creates** a new git branch
5. **Generates** infrastructure claim YAML files
6. **Creates** a Pull Request with the changes
7. **Updates** Port with the PR link and status

#### Expected Port Context

The workflow expects a `port_context` input with the following structure:

```json
{
  "payload": {
    "properties": {
      "bucketName": "portal-kombat-dev-example-12345",
      "environment": "dev",
      "region": "us-east-2",
      "versioning": true,
      "encryption": true,
      "purpose": "general"
    }
  },
  "context": {
    "runId": "run_xxxxxxxxxxxxx"
  }
}
```

#### Manual Testing

To test this workflow manually in GitHub Actions UI:

1. Go to **Actions** → **Create S3 Bucket from Port**
2. Click **Run workflow**
3. Paste the example JSON from `examples/port-context-s3-bucket-example.json`
4. Click **Run workflow**

**Expected Behavior:**

- ✅ Workflow will create branch, YAML files, and Pull Request
- ⚠️ Port API updates will be skipped or fail gracefully (expected)
- ✅ Final summary shows PR link and next steps

**Note:** Manual test runs use fake `runId` values that don't exist in Port, so Port entity updates will fail with 404 errors. This is expected and the workflow uses `continue-on-error: true` to complete successfully.

#### Port Configuration

The Port action is configured to call this workflow with:

```json
{
  "invocationMethod": {
    "type": "GITHUB",
    "workflow": "port-create-s3-bucket.yml",
    "workflowInputs": {
      "port_context": "{{ . | toJson }}"
    }
  }
}
```

The `{{ . | toJson }}` template passes the entire Port action context as JSON.

#### Required Secrets

- `PORT_CLIENT_ID` - Port API client ID
- `PORT_CLIENT_SECRET` - Port API client secret
- `GITHUB_TOKEN` - Automatically provided by GitHub Actions

#### Files Created

After successful execution, the workflow creates:

1. **Infrastructure Claim**: `environments/{env}/infrastructure/storage/{bucket-name}.yaml`
2. **Port Catalog Entry**: `environments/{env}/infrastructure/storage/{bucket-name}-port.yml`

### port-create-transit-gateway.yml

Creates a Transit Gateway infrastructure claim through GitOps.

**Trigger:** Port Self-Service Action
**Port Action Config:** `port/actions/create-transit-gateway.json`

Similar workflow pattern to S3 bucket creation.

## Troubleshooting

### Error: "Port context is empty or null"

This error occurs when:

1. **Testing manually without context**: Provide the example JSON from the `examples/` directory
2. **Port action misconfigured**: Check that `port/actions/*.json` has correct `workflowInputs`
3. **Port webhook not working**: Verify Port GitHub integration is active

### Error: "bucketName is required but was not provided"

The Port context is being received, but it's missing required fields. Check:

1. Port action user inputs are correctly defined
2. Port is passing the fields in `payload.properties`
3. The Port action form is filled out completely

### Error: Labels not found

This is a warning, not an error. The workflow tries to add labels to the PR but fails gracefully if they don't exist. To fix:

1. Create labels in your repository: `port`, `infrastructure`, `dev`, `staging`, `prod`
2. Or remove the label-adding steps from the workflow

## Development

### Adding a New Port Action Workflow

1. Create workflow file: `.github/workflows/port-{action}.yml`
2. Define `workflow_dispatch` trigger with `port_context` input
3. Parse Port context in first step with proper error handling
4. Implement your action logic
5. Update Port run status and entity at the end
6. Create Port action config: `port/actions/{action}.json`
7. Document in this README

### Testing Changes

Before pushing changes:

1. Test the workflow locally by reviewing the bash script logic
2. Create a test Port action in your Port workspace
3. Trigger the action and verify the workflow runs correctly
4. Check that Port entities are updated properly

## Resources

- [Port Documentation](https://docs.getport.io/)
- [Port GitHub Integration](https://docs.getport.io/build-your-software-catalog/sync-data-to-catalog/git/github/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
