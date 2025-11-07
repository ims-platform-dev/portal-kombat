# Phase 1 Integration Testing Guide

## Overview

This guide provides comprehensive instructions for integration testing Phase 1 of the AWS Routing Composition (Transit Gateway, VPC Attachments, and Route Tables).

## Prerequisites

### Cluster Access
- Active AWS SSO session with appropriate permissions
- `kubectl` configured to access the dev cluster
- ArgoCD deployed and operational
- Crossplane installed and healthy

### AWS Credentials
```bash
# Verify AWS credentials
aws sts get-caller-identity --region us-east-2

# Expected output:
# {
#   "UserId": "...",
#   "Account": "123456789012",
#   "Arn": "arn:aws:sts::123456789012:assumed-role/..."
# }
```

### Required Resources
- Existing VPC with labels:
  - `portal-kombat.io/network-component: vpc`
  - `environment: dev`
- Private subnets in VPC with label:
  - `tier: private`
- Subnets in multiple availability zones (recommended: us-east-2a, us-east-2b)

### Verify Prerequisites
```bash
# Check Crossplane is healthy
kubectl get providers
# All providers should show HEALTHY=True, INSTALLED=True

# Check for existing VPCs
kubectl get vpc -n crossplane-system --show-labels
# Should show at least one VPC with required labels

# Check for private subnets
kubectl get subnet -n crossplane-system -l tier=private
# Should show subnets in multiple AZs

# Verify AWS CLI access
aws ec2 describe-vpcs --region us-east-2 --filters "Name=tag:managedBy,Values=Crossplane"
```

## Test Cases

### Test Case 1: Basic Transit Gateway

**Objective:** Verify Transit Gateway can be provisioned with standard configuration.

**Steps:**
```bash
# 1. Apply Transit Gateway claim
kubectl apply -f examples/routing/phase1/01-transit-gateway.yaml

# 2. Wait for resource to become ready (max 5 minutes)
kubectl wait --for=condition=Ready transitgateway/dev-hub-tgw \
  -n crossplane-system --timeout=300s

# 3. Check claim status
kubectl get transitgateway dev-hub-tgw -n crossplane-system -o yaml

# 4. Verify connection secret was created
kubectl get secret dev-hub-tgw-connection -n crossplane-system
```

**Expected Outcomes:**
- TransitGateway claim reaches `Ready` status
- Status fields populated:
  - `status.atProvider.transitGatewayId`: `tgw-xxxxxxxxxxxxxxxxx`
  - `status.atProvider.ownerId`: AWS account ID
  - `status.atProvider.state`: `available`
  - `status.conditions[type=Ready].status`: `True`
- Connection secret created: `dev-hub-tgw-connection`
- Secret contains keys: `transitGatewayId`, `region`, `amazonSideAsn`

**AWS Validation:**
```bash
# Get Transit Gateway ID from status
TGW_ID=$(kubectl get transitgateway dev-hub-tgw -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayId}')

# Verify in AWS
aws ec2 describe-transit-gateways \
  --transit-gateway-ids $TGW_ID \
  --region us-east-2

# Expected output shows:
# - State: "available"
# - OwnerId: Your AWS account ID
# - Options.AmazonSideAsn: 64512
# - Options.DnsSupport: "enable"
# - Options.VpnEcmpSupport: "enable"
```

**Troubleshooting:**
```bash
# If status shows "Creating" for >5 minutes
kubectl describe transitgateway dev-hub-tgw -n crossplane-system
# Check Events section for errors

# If provider errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=50

# If IAM permission errors
kubectl get sa -n crossplane-system crossplane-aws-provider -o yaml
# Verify IRSA annotation is present
```

---

### Test Case 2: VPC Attachment with Subnet Selection

**Objective:** Verify VPC can be attached to Transit Gateway using selector-based binding.

**Steps:**
```bash
# 1. Apply Transit Gateway + Attachment
kubectl apply -f examples/routing/phase1/02-tgw-with-attachment.yaml

# 2. Wait for Transit Gateway to become ready
kubectl wait --for=condition=Ready transitgateway/dev-hub-tgw \
  -n crossplane-system --timeout=300s

# 3. Wait for attachment to become ready (max 10 minutes)
kubectl wait --for=condition=Ready transitgatewayattachment/dev-vpc1-attachment \
  -n crossplane-system --timeout=600s

# 4. Check attachment status
kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system -o yaml

# 5. Verify connection secret
kubectl get secret dev-vpc1-attachment-connection -n crossplane-system
```

**Expected Outcomes:**
- TransitGateway reaches `Ready` status
- TransitGatewayAttachment reaches `Ready` status
- Attachment status fields populated:
  - `status.atProvider.transitGatewayAttachmentId`: `tgw-attach-xxxxxxxxxxxxxxxxx`
  - `status.atProvider.state`: `available`
  - `status.atProvider.vpcId`: Matches selected VPC
  - `status.atProvider.subnetIds`: Array of private subnet IDs
  - `status.conditions[type=Ready].status`: `True`
- Connection secret contains: `transitGatewayAttachmentId`, `transitGatewayId`, `vpcId`, `subnetIds`

**Selector Validation:**
```bash
# Verify Transit Gateway selector matched correctly
TGW_ID=$(kubectl get transitgateway dev-hub-tgw -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayId}')
ATTACHMENT_TGW=$(kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayId}')

# TGW IDs should match
echo "Transit Gateway: $TGW_ID"
echo "Attachment TGW: $ATTACHMENT_TGW"
test "$TGW_ID" = "$ATTACHMENT_TGW" && echo "✅ Selector binding successful"

# Verify VPC selector matched correctly
VPC_ID=$(kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system \
  -o jsonpath='{.status.atProvider.vpcId}')
echo "Attached VPC: $VPC_ID"

# Verify subnets are private and span multiple AZs
SUBNET_IDS=$(kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system \
  -o jsonpath='{.status.atProvider.subnetIds[*]}')
echo "Attached Subnets: $SUBNET_IDS"

# Check subnet distribution across AZs
for subnet in $SUBNET_IDS; do
  aws ec2 describe-subnets --subnet-ids $subnet --region us-east-2 \
    --query 'Subnets[0].[SubnetId,AvailabilityZone,Tags[?Key==`tier`].Value|[0]]' \
    --output text
done
# Expected: One subnet per AZ, all tagged as "private"
```

**AWS Validation:**
```bash
# Get attachment ID
ATTACHMENT_ID=$(kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayAttachmentId}')

# Verify in AWS
aws ec2 describe-transit-gateway-vpc-attachments \
  --transit-gateway-attachment-ids $ATTACHMENT_ID \
  --region us-east-2

# Expected output shows:
# - State: "available"
# - VpcId: Your VPC ID
# - SubnetIds: Array of private subnet IDs
# - TransitGatewayId: Matches Transit Gateway
# - Association.State: "associated" (with default route table)
```

**Troubleshooting:**
```bash
# If selector cannot find Transit Gateway
kubectl get transitgateway -n crossplane-system --show-labels
# Verify labels match attachment's transitGatewaySelector

# If selector cannot find VPC
kubectl get vpc -n crossplane-system --show-labels
# Verify labels match attachment's vpcIdSelector

# If no subnets found
kubectl get subnet -n crossplane-system -l tier=private
# Verify private subnets exist with correct label

# If attachment stuck in "pending"
kubectl describe transitgatewayattachment dev-vpc1-attachment -n crossplane-system
# Check Events for subnet availability zone errors

# Check composition logs
kubectl get composite -n crossplane-system
kubectl logs -n crossplane-system -l crossplane.io/claim-name=dev-vpc1-attachment --tail=50
```

---

### Test Case 3: Route Table with Static Routes

**Objective:** Verify Transit Gateway Route Table can be created and associated with Transit Gateway.

**Steps:**
```bash
# 1. Apply Transit Gateway + Route Table
kubectl apply -f examples/routing/phase1/03-tgw-with-route-table.yaml

# 2. Wait for Transit Gateway
kubectl wait --for=condition=Ready transitgateway/dev-hub-tgw \
  -n crossplane-system --timeout=300s

# 3. Wait for Route Table (max 5 minutes)
kubectl wait --for=condition=Ready transitgatewayroutetable/dev-isolated-rt \
  -n crossplane-system --timeout=300s

# 4. Check route table status
kubectl get transitgatewayroutetable dev-isolated-rt -n crossplane-system -o yaml

# 5. Verify connection secret
kubectl get secret dev-isolated-rt-connection -n crossplane-system
```

**Expected Outcomes:**
- TransitGateway reaches `Ready` status
- TransitGatewayRouteTable reaches `Ready` status
- Route table status fields populated:
  - `status.atProvider.transitGatewayRouteTableId`: `tgw-rtb-xxxxxxxxxxxxxxxxx`
  - `status.atProvider.transitGatewayId`: Matches Transit Gateway
  - `status.atProvider.defaultAssociationRouteTable`: `false`
  - `status.atProvider.defaultPropagationRouteTable`: `false`
  - `status.conditions[type=Ready].status`: `True`
- Connection secret contains: `transitGatewayRouteTableId`, `transitGatewayId`

**Selector Validation:**
```bash
# Verify Transit Gateway selector matched
TGW_ID=$(kubectl get transitgateway dev-hub-tgw -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayId}')
RT_TGW=$(kubectl get transitgatewayroutetable dev-isolated-rt -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayId}')

echo "Transit Gateway: $TGW_ID"
echo "Route Table TGW: $RT_TGW"
test "$TGW_ID" = "$RT_TGW" && echo "✅ Route table bound to correct Transit Gateway"
```

**AWS Validation:**
```bash
# Get route table ID
RT_ID=$(kubectl get transitgatewayroutetable dev-isolated-rt -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayRouteTableId}')

# Verify in AWS
aws ec2 describe-transit-gateway-route-tables \
  --transit-gateway-route-table-ids $RT_ID \
  --region us-east-2

# Expected output shows:
# - State: "available"
# - TransitGatewayId: Matches Transit Gateway
# - DefaultAssociationRouteTable: false
# - DefaultPropagationRouteTable: false
# - Tags include managedBy: Crossplane

# Check routes in table (should be empty for Phase 1 basic test)
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id $RT_ID \
  --filters "Name=state,Values=active" \
  --region us-east-2
```

**Troubleshooting:**
```bash
# If selector cannot find Transit Gateway
kubectl get transitgateway -n crossplane-system --show-labels
# Verify labels match route table's transitGatewaySelector

# If route table stuck in "Creating"
kubectl describe transitgatewayroutetable dev-isolated-rt -n crossplane-system
# Check Events section

# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=50 | grep -i "route table"
```

---

### Test Case 4: End-to-End Provisioning

**Objective:** Verify complete Transit Gateway infrastructure can be provisioned in correct order.

**Steps:**
```bash
# 1. Apply all resources together
kubectl apply -f examples/routing/phase1/

# 2. Monitor resource creation order
watch kubectl get transitgateway,transitgatewayattachment,transitgatewayroutetable \
  -n crossplane-system

# 3. Wait for all resources (max 15 minutes)
kubectl wait --for=condition=Ready transitgateway/dev-hub-tgw \
  -n crossplane-system --timeout=900s
kubectl wait --for=condition=Ready transitgatewayattachment -A --timeout=900s
kubectl wait --for=condition=Ready transitgatewayroutetable -A --timeout=900s

# 4. Verify all connection secrets
kubectl get secrets -n crossplane-system | grep -E "(tgw|attachment|route.*table)"
```

**Expected Outcomes:**
- Resources provision in dependency order:
  1. Transit Gateway (independent)
  2. Route Table (depends on Transit Gateway via selector)
  3. VPC Attachment (depends on Transit Gateway via selector)
- All resources reach `Ready` status
- All connection secrets created
- No error events in any resource

**Comprehensive Validation:**
```bash
# Check all Transit Gateway infrastructure
TGW_ID=$(kubectl get transitgateway dev-hub-tgw -n crossplane-system \
  -o jsonpath='{.status.atProvider.transitGatewayId}')

# List all attachments
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
  --region us-east-2 \
  --query 'TransitGatewayAttachments[*].[TransitGatewayAttachmentId,ResourceId,State,ResourceType]' \
  --output table

# List all route tables
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
  --region us-east-2 \
  --query 'TransitGatewayRouteTables[*].[TransitGatewayRouteTableId,State,DefaultAssociationRouteTable]' \
  --output table

# Verify attachment associations
for attachment in $(aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=$TGW_ID" \
  --region us-east-2 --query 'TransitGatewayAttachments[*].TransitGatewayAttachmentId' --output text); do
  echo "Attachment: $attachment"
  aws ec2 describe-transit-gateway-attachments \
    --transit-gateway-attachment-ids $attachment \
    --region us-east-2 \
    --query 'TransitGatewayAttachments[0].Association' \
    --output json
done
```

**Network Connectivity Test (Optional):**
```bash
# NOTE: Requires VPC route tables configured to route traffic through Transit Gateway
# This is typically done outside Crossplane (VPC managed resources or Terraform)

# 1. Get VPC CIDR
VPC_ID=$(kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system \
  -o jsonpath='{.status.atProvider.vpcId}')
VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --region us-east-2 \
  --query 'Vpcs[0].CidrBlock' --output text)

echo "VPC $VPC_ID has CIDR: $VPC_CIDR"

# 2. Check VPC route tables for Transit Gateway routes
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --region us-east-2 \
  --query 'RouteTables[*].Routes[?TransitGatewayId!=`null`]' \
  --output json
# If empty, VPC route tables need to be updated to route traffic through TGW
```

---

## Automated Testing

For automated testing, use the provided scripts:

```bash
# Run all integration tests
./examples/routing/phase1/run-integration-tests.sh

# Run specific test case
./examples/routing/phase1/run-integration-tests.sh --test-case 1

# Cleanup after testing
./examples/routing/phase1/cleanup-integration-tests.sh
```

## Common Issues and Solutions

### Issue: Resources stuck in "Creating" state

**Symptoms:**
- `kubectl get` shows resource in Creating state for >10 minutes
- No error messages in Events

**Diagnosis:**
```bash
kubectl describe <resource-type> <resource-name> -n crossplane-system
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=100
```

**Common Causes:**
1. IAM permissions missing for Crossplane provider
2. AWS service limits reached (e.g., max Transit Gateways per region)
3. Resource dependencies not satisfied (e.g., VPC not ready)
4. AWS API throttling

**Solutions:**
- Check IAM role permissions in `shared/managed-resources/iam-roles/iam-policies/`
- Verify AWS service quotas: `aws service-quotas list-service-quotas --service-code ec2`
- Check resource dependencies: `kubectl get managed -n crossplane-system`
- Wait and retry if API throttling

---

### Issue: Selector cannot find resources

**Symptoms:**
- `kubectl describe` shows "cannot resolve references"
- Status shows "Waiting for dependency"

**Diagnosis:**
```bash
# Check if target resource exists
kubectl get transitgateway -n crossplane-system --show-labels
kubectl get vpc -n crossplane-system --show-labels
kubectl get subnet -n crossplane-system -l tier=private

# Compare labels with selector
kubectl get <resource-type> <resource-name> -n crossplane-system -o yaml | grep -A5 selector
```

**Common Causes:**
1. Target resource doesn't exist
2. Target resource labels don't match selector
3. Target resource in different namespace
4. Resource not yet ready (timing issue)

**Solutions:**
- Create target resource first
- Update labels to match selector (use `kubectl label`)
- Ensure all resources in same namespace
- Wait for dependencies to reach Ready state before applying dependent resources

---

### Issue: Connection secret not created

**Symptoms:**
- Resource is Ready but connection secret missing
- `kubectl get secret <resource-name>-connection -n crossplane-system` returns not found

**Diagnosis:**
```bash
kubectl get <resource-type> <resource-name> -n crossplane-system -o yaml | grep -A10 writeConnectionSecretToRef
kubectl get events -n crossplane-system --field-selector involvedObject.name=<resource-name>
```

**Common Causes:**
1. `writeConnectionSecretToRef` not specified in composition
2. Crossplane RBAC insufficient
3. Secret namespace doesn't exist
4. AWS resource doesn't expose required fields

**Solutions:**
- Verify composition includes `writeConnectionSecretToRef`
- Check Crossplane service account permissions
- Create namespace if missing
- Review composition field mapping in `platform/compositions/routing/`

---

### Issue: AWS resources exist but Crossplane shows "not found"

**Symptoms:**
- AWS console shows Transit Gateway exists
- Crossplane claim shows "not found" or "creating"

**Diagnosis:**
```bash
# Get AWS resource ID from console or CLI
TGW_ID="tgw-xxxxxxxxxxxxxxxxx"

# Check if Crossplane has a managed resource for it
kubectl get transitgateways.ec2.aws.crossplane.io -A -o yaml | grep $TGW_ID

# Check provider logs for reconciliation errors
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=100 | grep $TGW_ID
```

**Common Causes:**
1. Resource created outside Crossplane (manual or Terraform)
2. Provider configuration pointing to wrong AWS account/region
3. IAM permissions insufficient to describe resource
4. Resource tags don't match Crossplane's external name annotation

**Solutions:**
- Import existing resources using Crossplane's external name annotation
- Verify provider config: `kubectl get providerconfigs -n crossplane-system -o yaml`
- Check IAM permissions include `ec2:DescribeTransitGateways`
- Tag AWS resources with `crossplane-kind` and `crossplane-name`

---

## Performance Benchmarks

Expected provisioning times:

| Resource Type | Typical Time | Max Time |
|---------------|--------------|----------|
| Transit Gateway | 2-3 minutes | 5 minutes |
| VPC Attachment | 5-7 minutes | 10 minutes |
| Route Table | 1-2 minutes | 5 minutes |
| End-to-End Stack | 8-12 minutes | 15 minutes |

If resources exceed max time consistently, investigate:
- AWS API throttling (check CloudTrail)
- Crossplane provider resource limits
- Network connectivity issues
- AWS region health status

## Cleanup Verification

After cleanup, verify all resources removed:

```bash
# Check Crossplane resources
kubectl get transitgateway,transitgatewayattachment,transitgatewayroutetable -A
# Should return "No resources found"

# Check AWS resources (using IDs captured during testing)
aws ec2 describe-transit-gateways --transit-gateway-ids $TGW_ID --region us-east-2
# Should return error: "The transitGateway ID 'tgw-xxx' does not exist"

# Check for orphaned attachments
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=state,Values=available,deleting,pending" \
  --region us-east-2 \
  --query 'TransitGatewayAttachments[?Tags[?Key==`project`&&Value==`portal-kombat`]]'
# Should return empty array []

# Verify no orphaned route tables
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=tag:project,Values=portal-kombat" \
  --region us-east-2
# Should return empty array []
```

## Next Steps

After successful Phase 1 integration testing:

1. **Document Results**: Record test outcomes, timings, and any issues encountered
2. **Promote to Staging**: Apply Phase 1 resources to staging environment
3. **Phase 2 Planning**: Review Phase 2 features (BGP, dynamic routing, route propagation)
4. **Production Readiness**: Evaluate if Phase 1 meets production requirements or if Phase 2 needed

## Support

For issues not covered in this guide:
- Review composition definitions: `platform/compositions/routing/`
- Check XRD specifications: `platform/xrds/routing/`
- Consult AWS Transit Gateway documentation
- Review Crossplane provider documentation

## Test Report Template

After testing, document results:

```markdown
# Phase 1 Integration Test Report

**Date:** YYYY-MM-DD
**Tester:** Name
**Environment:** dev
**Cluster:** portal-kombat-dev

## Test Results

| Test Case | Status | Time | Notes |
|-----------|--------|------|-------|
| Basic Transit Gateway | ✅ Pass | 3m15s | - |
| VPC Attachment | ✅ Pass | 6m42s | - |
| Route Table | ✅ Pass | 2m08s | - |
| End-to-End | ✅ Pass | 12m05s | - |

## Resource IDs

- Transit Gateway: tgw-xxxxxxxxxxxxxxxxx
- VPC Attachment: tgw-attach-xxxxxxxxxxxxxxxxx
- Route Table: tgw-rtb-xxxxxxxxxxxxxxxxx

## Issues Encountered

None / [List any issues]

## Recommendations

[Any improvements or observations]

## Cleanup Status

✅ All resources deleted successfully
```
