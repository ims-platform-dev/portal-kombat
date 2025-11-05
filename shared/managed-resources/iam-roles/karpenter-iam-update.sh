#!/bin/bash
# Update IAM permissions for Karpenter controller
# This script attaches the Karpenter controller policy to the existing IRSA role

set -e

# Configuration
CLUSTER_NAME="raiden-control-plane"
AWS_REGION="us-east-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_NAME="karpenter-controller-policy"
ROLE_NAME="karpenter_controller_role-${CLUSTER_NAME}"

echo "=== Karpenter IAM Policy Update ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "Role: $ROLE_NAME"
echo ""

# Check if role exists
if ! aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
  echo "❌ ERROR: Role $ROLE_NAME does not exist."
  echo "Please ensure the Karpenter IRSA role has been created first."
  exit 1
fi

echo "✅ Found existing role: $ROLE_NAME"

# Create or update the IAM policy
echo ""
echo "Creating/updating IAM policy: $POLICY_NAME"
POLICY_ARN=$(aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://$(dirname $0)/iam-policies/karpenter-controller-policy.json \
  --query 'Policy.Arn' \
  --output text 2>/dev/null || \
  aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

if [ -z "$POLICY_ARN" ]; then
  echo "❌ ERROR: Failed to create or find policy"
  exit 1
fi

echo "✅ Policy ARN: $POLICY_ARN"

# Attach policy to role
echo ""
echo "Attaching policy to role..."
if aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN 2>/dev/null; then
  echo "✅ Policy attached successfully"
else
  echo "⚠️  Policy might already be attached (this is OK)"
fi

# List all attached policies for verification
echo ""
echo "Current policies attached to $ROLE_NAME:"
aws iam list-attached-role-policies --role-name $ROLE_NAME --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' --output table

echo ""
echo "✅ IAM policy update complete!"
echo ""
echo "Next steps:"
echo "1. Restart Karpenter pods to pick up new permissions:"
echo "   kubectl rollout restart deployment dev-k8s-karpenter -n karpenter"
echo ""
echo "2. Verify permissions by checking controller logs:"
echo "   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -c controller --tail=50"
