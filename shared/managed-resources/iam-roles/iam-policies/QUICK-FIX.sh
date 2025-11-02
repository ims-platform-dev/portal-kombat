#!/bin/bash
# Quick fix script for Crossplane IAM permissions
# This attaches AdministratorAccess for testing (NOT for production!)

set -e

echo "================================================"
echo "Crossplane IAM Permissions Quick Fix"
echo "================================================"
echo ""
echo "⚠️  WARNING: This grants full AWS access!"
echo "    Only use for testing/development"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Step 1: Attaching AdministratorAccess policy..."
aws iam attach-role-policy \
  --role-name crossplane-sa-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "✓ Policy attached"
echo ""

echo "Step 2: Verifying attached policies..."
aws iam list-attached-role-policies --role-name crossplane-sa-role
echo ""

echo "Step 3: Restarting AWS provider pod..."
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws
echo "✓ Pod deleted, waiting for restart..."
echo ""

echo "Waiting 10 seconds for pod to restart..."
sleep 10

echo "Step 4: Checking pod status..."
kubectl get pods -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws
echo ""

echo "Step 5: Checking for errors in logs..."
echo "Last 20 lines of provider logs:"
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws --tail=20
echo ""

echo "================================================"
echo "✓ Fix complete!"
echo ""
echo "Next steps:"
echo "1. Check logs for any remaining errors:"
echo "   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=crossplane-provider-aws"
echo ""
echo "2. Test with a simple S3 bucket:"
echo "   kubectl apply -f examples/crossplane/01-s3-bucket.yaml"
echo "   kubectl get bucket -w"
echo ""
echo "3. For production, replace AdministratorAccess with:"
echo "   See iam-policies/SETUP-INSTRUCTIONS.md"
echo "================================================"
