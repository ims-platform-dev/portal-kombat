#!/bin/bash
# Setup IRSA for cert-manager to use Route53
# This script creates the IAM role and policy for cert-manager

set -e

# Configuration
CLUSTER_NAME="raiden-control-plane"  # TODO: Update with your EKS cluster name
AWS_REGION="us-east-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_NAME="cert-manager-route53-policy"
ROLE_NAME="cert-manager-sa-role"
NAMESPACE="cert-manager"
SERVICE_ACCOUNT="dev-k8s-cert-manager"

echo "Creating IAM policy: $POLICY_NAME"
POLICY_ARN=$(aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://$(dirname $0)/iam-policies/cert-manager-route53-policy.json \
  --query 'Policy.Arn' \
  --output text 2>/dev/null || \
  aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)

echo "Policy ARN: $POLICY_ARN"

# Get OIDC provider URL
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION \
  --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")

echo "OIDC Provider: $OIDC_PROVIDER"

# Create trust policy
cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT}",
          "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
EOF

echo "Creating IAM role: $ROLE_NAME"
ROLE_ARN=$(aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --query 'Role.Arn' \
  --output text 2>/dev/null || \
  aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)

echo "Role ARN: $ROLE_ARN"

# Attach policy to role
echo "Attaching policy to role..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN

echo ""
echo "✅ IAM Role created successfully!"
echo ""
echo "Next steps:"
echo "1. Annotate the cert-manager service account:"
echo "   kubectl annotate serviceaccount $SERVICE_ACCOUNT -n $NAMESPACE \\"
echo "     eks.amazonaws.com/role-arn=$ROLE_ARN --overwrite"
echo ""
echo "2. Restart cert-manager pods to pick up the role:"
echo "   kubectl rollout restart deployment -n cert-manager"
echo ""
echo "3. Verify the annotation:"
echo "   kubectl describe sa $SERVICE_ACCOUNT -n $NAMESPACE | grep Annotations"

# Cleanup
rm -f /tmp/trust-policy.json
