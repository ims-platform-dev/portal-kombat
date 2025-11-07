#!/bin/bash
# Test script for Port.io S3 provisioning workflow
# Simulates Port.io payload to test GitHub Actions workflow manually

set -e

# Port.io payload structure that would be sent by Port.io GitHub backend
PORT_PAYLOAD='{
  "action": "provision_s3_bucket",
  "resourceType": "run",
  "status": "TRIGGERED",
  "trigger": {
    "by": {
      "user": {
        "email": "test-user@example.com",
        "firstName": "Test",
        "lastName": "User"
      }
    },
    "origin": "UI",
    "at": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
  },
  "context": {
    "entity": null,
    "blueprint": "s3-bucket",
    "runId": "test-run-'$(date +%s)'"
  },
  "payload": {
    "entity": null,
    "action": {
      "identifier": "provision_s3_bucket",
      "title": "Provision S3 Bucket"
    },
    "properties": {
      "purpose": "test-bucket",
      "environment": "dev",
      "team": "platform-engineering",
      "bucketName": "portal-kombat-dev-test-'$(date +%s)'",
      "region": "us-east-2",
      "versioning": false,
      "encryption": "AES256",
      "lifecyclePolicy": "none",
      "publicAccess": false,
      "costCenter": "engineering",
      "justification": "Testing Port.io integration workflow"
    }
  }
}'

echo "🚀 Testing Port.io S3 Provisioning Workflow"
echo ""
echo "Payload:"
echo "$PORT_PAYLOAD" | jq '.'
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo "❌ Error: GitHub CLI (gh) is not installed"
    echo "Install: brew install gh"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo "❌ Error: Not authenticated with GitHub"
    echo "Run: gh auth login"
    exit 1
fi

echo "Triggering workflow..."
echo ""

# Trigger the workflow
gh workflow run port-s3-provisioning.yaml \
  --field port_payload="$PORT_PAYLOAD"

if [ $? -eq 0 ]; then
    echo "✅ Workflow triggered successfully!"
    echo ""
    echo "Monitor workflow progress:"
    echo "  gh run list --workflow=port-s3-provisioning.yaml"
    echo "  gh run watch"
    echo ""
    echo "Or view in browser:"
    echo "  gh run list --workflow=port-s3-provisioning.yaml --web"
else
    echo "❌ Failed to trigger workflow"
    exit 1
fi
