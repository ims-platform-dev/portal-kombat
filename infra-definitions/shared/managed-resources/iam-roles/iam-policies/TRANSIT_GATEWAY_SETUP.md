# Transit Gateway IAM Setup Instructions

This guide explains how to configure IAM permissions for AWS Transit Gateway management via Crossplane.

## Overview

The Transit Gateway composition requires additional IAM permissions beyond basic EC2 access. These permissions enable Crossplane to manage Transit Gateways, VPC attachments, route tables, and routing configurations.

## Prerequisites

- EKS cluster running with IRSA (IAM Roles for Service Accounts) configured
- Crossplane installed in `crossplane-system` namespace
- AWS Provider EC2 package installed (`provider-aws-ec2`)

## IAM Policy

The required IAM policy is provided in `crossplane-transit-gateway-policy.json` in this directory.

### Policy Structure

The policy includes six permission groups:

1. **TransitGatewayManagement**: Core Transit Gateway lifecycle operations
   - Create, delete, describe, and modify Transit Gateways
   - Modify Transit Gateway options (ASN, DNS support, route tables)

2. **TransitGatewayAttachmentManagement**: VPC attachment operations
   - Create and delete VPC attachments
   - Accept and reject attachment requests (for cross-account scenarios)
   - Modify attachment configurations

3. **TransitGatewayRouteTableManagement**: Route table operations
   - Create and delete route tables
   - Associate and disassociate attachments to route tables
   - Enable and disable route propagation
   - Query propagations and associations

4. **TransitGatewayRouteManagement**: Route operations
   - Create, delete, and replace static routes
   - Search routes in route tables

5. **VPCReadAccess**: Required read-only VPC permissions
   - Describe VPCs, subnets, availability zones
   - Required for attachment validation and selector resolution

6. **ResourceTagging**: Tag management for Transit Gateway resources
   - Apply and remove tags for resource organization
   - Required for Crossplane resource tracking

### Regional Restrictions

The policy includes regional restrictions limiting Transit Gateway operations to:
- `us-east-1` (N. Virginia)
- `us-east-2` (Ohio)
- `us-west-2` (Oregon)

**To modify regions**: Edit the `Condition` blocks in the policy JSON:

```json
"Condition": {
  "StringEquals": {
    "aws:RequestedRegion": [
      "us-east-1",
      "us-east-2",
      "us-west-2",
      "eu-west-1"  // Add your regions here
    ]
  }
}
```

## Setup Steps

### 1. Create IAM Policy

Create the IAM policy in your AWS account:

```bash
aws iam create-policy \
  --policy-name CrossplaneTransitGatewayPolicy \
  --policy-document file://crossplane-transit-gateway-policy.json \
  --description "Permissions for Crossplane to manage AWS Transit Gateway resources"
```

**Note the Policy ARN** from the output - you'll need it in the next step.

### 2. Attach Policy to Crossplane IAM Role

#### Option A: Using Terraform (Recommended)

If you're using Terraform to manage your EKS cluster and Crossplane IRSA:

```hcl
# Add to your Terraform configuration
data "aws_iam_policy" "transit_gateway" {
  name = "CrossplaneTransitGatewayPolicy"
}

resource "aws_iam_role_policy_attachment" "crossplane_transit_gateway" {
  role       = module.crossplane_irsa.iam_role_name  # Your Crossplane IRSA role
  policy_arn = data.aws_iam_policy.transit_gateway.arn
}
```

#### Option B: Using AWS CLI

```bash
# Get your Crossplane IRSA role name
ROLE_NAME=$(aws iam list-roles --query "Roles[?contains(RoleName, 'crossplane')].RoleName" --output text)

# Attach the policy
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::YOUR-ACCOUNT-ID:policy/CrossplaneTransitGatewayPolicy
```

### 3. Verify Provider Configuration

Ensure your AWS Provider EC2 is using the correct ProviderConfig with IRSA:

```yaml
apiVersion: aws.crossplane.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: InjectedIdentity  # Uses IRSA
```

**Check provider config**:

```bash
kubectl get providerconfig default -o yaml
```

### 4. Verify Provider Pod Identity

Confirm the provider pod is using the correct service account with IRSA:

```bash
# Check service account annotation
kubectl get sa -n crossplane-system provider-aws-ec2 -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Should output: arn:aws:iam::YOUR-ACCOUNT-ID:role/crossplane-sa-role
```

### 5. Restart Provider Pod

After attaching the policy, restart the provider pod to pick up new permissions:

```bash
kubectl delete pod -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l pkg.crossplane.io/provider=provider-aws-ec2 -n crossplane-system --timeout=120s
```

## Verification

### Test Basic Transit Gateway Creation

Create a test Transit Gateway to verify permissions:

```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: TransitGateway
metadata:
  name: test-permissions-tgw
  labels:
    portal-kombat.io/test: "true"
spec:
  parameters:
    amazonSideAsn: 64512
    dnsSupport: true
    defaultRouteTableAssociation: false
    defaultRouteTablePropagation: false
    region: us-east-2
```

Apply the test:

```bash
kubectl apply -f test-tgw.yaml

# Check status
kubectl describe transitgateway test-permissions-tgw

# Look for Ready condition
kubectl get transitgateway test-permissions-tgw -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Should output: True
```

### Check AWS Console

Verify the Transit Gateway appears in AWS:

```bash
aws ec2 describe-transit-gateways \
  --filters "Name=tag:crossplane-name,Values=test-permissions-tgw" \
  --region us-east-2
```

### Clean Up Test

```bash
kubectl delete transitgateway test-permissions-tgw
```

## Troubleshooting

### Permission Denied Errors

If you see errors like:

```
cannot create TransitGateway: UnauthorizedOperation: You are not authorized to perform this operation
```

**Solutions**:

1. **Verify policy is attached**:
   ```bash
   aws iam list-attached-role-policies --role-name crossplane-sa-role
   ```

2. **Check IRSA configuration**:
   ```bash
   kubectl get sa provider-aws-ec2 -n crossplane-system -o yaml
   ```

3. **Restart provider pod** (see step 5 above)

4. **Check provider logs**:
   ```bash
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=50
   ```

### Regional Restrictions

If operations fail in specific regions:

```
cannot create TransitGateway: UnauthorizedOperation: The operation is not permitted in this region
```

**Solution**: Add the region to the policy's `Condition` blocks (see "Regional Restrictions" above).

### Insufficient VPC Permissions

If attachment creation fails with VPC-related errors:

```
cannot create TransitGatewayVpcAttachment: UnauthorizedOperation: You are not authorized to describe VPCs
```

**Solution**: Ensure the `VPCReadAccess` statement in the policy includes all necessary describe actions.

## Least Privilege Recommendations

### Resource-Level Restrictions (Optional)

For enhanced security, you can restrict Transit Gateway operations to specific resource ARNs:

```json
{
  "Sid": "TransitGatewayManagement",
  "Effect": "Allow",
  "Action": ["ec2:CreateTransitGateway", "ec2:DeleteTransitGateway"],
  "Resource": "arn:aws:ec2:*:*:transit-gateway/*",
  "Condition": {
    "StringEquals": {
      "aws:RequestTag/ManagedBy": "Crossplane"
    }
  }
}
```

**Note**: This requires all Transit Gateway resources to be tagged with `ManagedBy=Crossplane` at creation time.

### Cross-Account Scenarios

For cross-account Transit Gateway sharing:

1. **In the Transit Gateway owning account**: Grant `ec2:ModifyTransitGateway` and `ram:*` permissions
2. **In the consuming account**: Grant `ec2:AcceptTransitGatewayVpcAttachment` permission
3. Configure RAM (Resource Access Manager) sharing policies

## Multi-Account Setup

### Hub Account (Transit Gateway Owner)

```json
{
  "Sid": "AllowRAMSharing",
  "Effect": "Allow",
  "Action": [
    "ram:CreateResourceShare",
    "ram:DeleteResourceShare",
    "ram:AssociateResourceShare",
    "ram:DisassociateResourceShare",
    "ram:GetResourceShares",
    "ram:TagResource"
  ],
  "Resource": "*"
}
```

### Spoke Accounts (VPC Attachment Creators)

Use the standard `crossplane-transit-gateway-policy.json` with attachment permissions.

## Integration with Existing Policies

If you already have a Crossplane IAM policy, you can merge the Transit Gateway permissions:

```bash
# Download existing policy
aws iam get-policy-version \
  --policy-arn arn:aws:iam::YOUR-ACCOUNT-ID:policy/CrossplaneEC2Policy \
  --version-id v1 > existing-policy.json

# Merge statements manually, then update
aws iam create-policy-version \
  --policy-arn arn:aws:iam::YOUR-ACCOUNT-ID:policy/CrossplaneEC2Policy \
  --policy-document file://merged-policy.json \
  --set-as-default
```

## Security Best Practices

1. **Use Regional Restrictions**: Limit operations to specific AWS regions
2. **Enable CloudTrail**: Monitor Transit Gateway API calls
3. **Tag Resources**: Always tag Transit Gateway resources for tracking and cost allocation
4. **Rotate Credentials**: Even with IRSA, periodically review IAM permissions
5. **Principle of Least Privilege**: Start with minimal permissions, add as needed
6. **Separate Policies**: Keep Transit Gateway permissions in a dedicated policy for easier management

## Cost Considerations

Transit Gateway operations incur costs:
- **Hourly charge**: Per Transit Gateway per hour (~$0.05/hour in us-east-1)
- **Data processing**: Per GB processed through attachments (~$0.02/GB)

**Recommendation**: Use tagging to track costs:

```yaml
spec:
  parameters:
    tags:
      - key: CostCenter
        value: networking
      - key: Environment
        value: dev
      - key: ManagedBy
        value: Crossplane
```

## References

- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [Transit Gateway Quotas](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html)
- [Crossplane AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-aws/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [Portal Kombat Routing Documentation](docs/ROUTING_COMPOSITION.md)

## Support

For issues with IAM permissions or Transit Gateway setup:
1. Check provider logs: `kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2`
2. Review CloudTrail for IAM permission denials
3. Verify IRSA configuration is correct
4. Consult the comprehensive routing documentation: `docs/ROUTING_COMPOSITION.md`
