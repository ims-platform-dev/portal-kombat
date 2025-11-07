#!/bin/bash
# Create Port.io self-service action for S3 bucket provisioning

set -e

echo "🚀 Creating Port.io Self-Service Action"
echo ""

# Port.io credentials
CLIENT_ID="gWVcpoKHEkXO08XA9kkXzuIATv5POjij"
CLIENT_SECRET="OntDC9LMg780GlKwZYZxIEknQMbZnYQ5nM7HX8wWfBG8TtvKRsy13xcZg8y8sILy"
API_BASE="https://api.us.getport.io"

# Get authentication token
echo "1️⃣ Authenticating with Port.io..."
TOKEN_RESPONSE=$(curl -s -X POST "${API_BASE}/v1/auth/access_token" \
  -H "Content-Type: application/json" \
  -d "{\"clientId\":\"${CLIENT_ID}\",\"clientSecret\":\"${CLIENT_SECRET}\"}")

TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.accessToken')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo "❌ Failed to authenticate with Port.io"
    echo "Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "✅ Authenticated successfully"
echo ""

# Create the action
echo "2️⃣ Creating self-service action on s3-bucket blueprint..."
ACTION_CONFIG="config/port-io/actions/provision-s3-bucket-simple.json"

if [ ! -f "$ACTION_CONFIG" ]; then
    echo "❌ Action config file not found: $ACTION_CONFIG"
    exit 1
fi

# Create or update the action (using new API endpoint)
RESPONSE=$(curl -s -X POST "${API_BASE}/v1/actions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d @"${ACTION_CONFIG}")

# Check if action was created
ACTION_ID=$(echo "$RESPONSE" | jq -r '.action.identifier // empty')

if [ -z "$ACTION_ID" ]; then
    # Check if it already exists
    ERROR=$(echo "$RESPONSE" | jq -r '.message // empty')
    if [[ "$ERROR" == *"already exists"* ]]; then
        echo "⚠️  Action already exists, updating instead..."

        # Update existing action (using new API endpoint)
        RESPONSE=$(curl -s -X PATCH "${API_BASE}/v1/actions/provision_s3_bucket" \
          -H "Authorization: Bearer ${TOKEN}" \
          -H "Content-Type: application/json" \
          -d @"${ACTION_CONFIG}")

        ACTION_ID=$(echo "$RESPONSE" | jq -r '.action.identifier // empty')
    else
        echo "❌ Failed to create action"
        echo "Response: $RESPONSE"
        exit 1
    fi
fi

if [ -z "$ACTION_ID" ]; then
    echo "❌ Failed to create or update action"
    echo "Response: $RESPONSE"
    exit 1
fi

echo "✅ Action created/updated successfully"
echo ""

# Display action details
echo "3️⃣ Action Details:"
echo "   Identifier: provision_s3_bucket"
echo "   Title: Provision S3 Bucket"
echo "   Blueprint: s3-bucket"
echo "   Backend: GitHub (ims-platform-dev/portal-kombat)"
echo "   Workflow: port-s3-provisioning.yaml"
echo ""

echo "✅ Setup Complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Go to Port.io: https://app.us.getport.io"
echo "2. Navigate to: Builder → Self-service → Actions"
echo "3. You should see: 'Provision S3 Bucket' action"
echo "4. Go to: Catalog → S3 Buckets"
echo "5. Click: Actions → Provision S3 Bucket"
echo "6. Fill the form and click Execute"
echo ""
echo "🎯 Expected Flow:"
echo "   Port.io → GitHub Workflow → PR → ArgoCD → Crossplane → AWS S3"
echo ""
