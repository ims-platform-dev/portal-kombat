# AWS Routing Phase 1 Examples

This directory contains example claims demonstrating Phase 1 of the AWS Routing capability, focusing on Transit Gateway provisioning, VPC attachments, and route table management.

## Overview

Phase 1 provides three core routing resources:

1. **TransitGateway**: Hub router for connecting multiple VPCs and on-premises networks
2. **TransitGatewayAttachment**: Connects VPCs to Transit Gateways using selector-based binding
3. **TransitGatewayRouteTable**: Manages routing tables with static route support

## Prerequisites

### Required Resources

Before deploying these examples, ensure you have:

1. **VPC Resources**: The attachment examples require existing VPC resources with proper labels
2. **Crossplane Providers**: AWS provider family installed and configured
3. **XRDs Installed**: Transit Gateway XRDs deployed from `platform/xrds/routing/`

### Label Taxonomy

Resources use the following label patterns:

- `portal-kombat.io/network-component`: Resource type (vpc, transit-gateway, etc.)
- `environment`: Environment name (dev, staging, prod)
- `tier`: Network tier (public, private, database)

## Examples

### 01-transit-gateway.yaml

Simple Transit Gateway with basic configuration.

**Features:**
- Configurable ASN (Autonomous System Number)
- DNS support enabled
- VPN ECMP support for multi-tunnel VPN connections
- Environment-specific tagging

**Usage:**
```bash
kubectl apply -f 01-transit-gateway.yaml
```

**Validation:**
```bash
# Check claim status
kubectl get transitgateway dev-hub-tgw -n crossplane-system

# View AWS resource
kubectl get transitgateways.ec2.aws.crossplane.io

# Check events
kubectl describe transitgateway dev-hub-tgw -n crossplane-system
```

### 02-tgw-with-attachment.yaml

Transit Gateway with VPC attachment using selector-based resource binding.

**Features:**
- Transit Gateway provisioning
- Automatic VPC attachment using selectors
- Subnet tier selection (private subnets only)
- Label-based resource binding

**Prerequisites:**
```bash
# Requires VPC with matching labels:
# - portal-kombat.io/network-component: vpc
# - environment: dev
# And private subnets with tier: private label
```

**Usage:**
```bash
kubectl apply -f 02-tgw-with-attachment.yaml
```

**Validation:**
```bash
# Check both resources
kubectl get transitgateway dev-hub-tgw -n crossplane-system
kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system

# Check AWS attachment resource
kubectl get transitgatewayvpcattachments.ec2.aws.crossplane.io

# Verify attachment is associated with Transit Gateway
kubectl describe transitgatewayattachment dev-vpc1-attachment -n crossplane-system
```

### 03-tgw-with-route-table.yaml

Transit Gateway with route table for traffic segmentation.

**Features:**
- Transit Gateway provisioning
- Route table creation
- Automatic Transit Gateway binding using selectors
- Static route support (Phase 1)

**Note:** Phase 1 supports static routes only. Dynamic routing (BGP) will be added in Phase 2.

**Usage:**
```bash
kubectl apply -f 03-tgw-with-route-table.yaml
```

**Validation:**
```bash
# Check all resources
kubectl get transitgateway dev-hub-tgw -n crossplane-system
kubectl get transitgatewayroutetable dev-isolated-rt -n crossplane-system

# Check AWS route table resource
kubectl get transitgatewayroutetables.ec2.aws.crossplane.io

# Verify route table is associated with Transit Gateway
kubectl describe transitgatewayroutetable dev-isolated-rt -n crossplane-system
```

## Common Workflows

### Deploy Complete Hub-and-Spoke Network

```bash
# 1. Deploy Transit Gateway
kubectl apply -f 01-transit-gateway.yaml

# 2. Wait for Transit Gateway to be ready
kubectl wait --for=condition=Ready transitgateway/dev-hub-tgw -n crossplane-system --timeout=300s

# 3. Deploy VPC attachments (requires existing VPCs)
kubectl apply -f 02-tgw-with-attachment.yaml

# 4. Deploy route tables for traffic segmentation
kubectl apply -f 03-tgw-with-route-table.yaml
```

### Validate All Resources

```bash
# Check all Transit Gateway resources
kubectl get transitgateway -n crossplane-system
kubectl get transitgatewayattachment -n crossplane-system
kubectl get transitgatewayroutetable -n crossplane-system

# Check AWS managed resources
kubectl get managed | grep transitgateway
```

### Clean Up

```bash
# Delete in reverse order to avoid dependency issues
kubectl delete -f 03-tgw-with-route-table.yaml
kubectl delete -f 02-tgw-with-attachment.yaml
kubectl delete -f 01-transit-gateway.yaml
```

## Troubleshooting

### Transit Gateway Not Ready

**Symptoms:**
- TransitGateway claim stuck in "Provisioning" state
- Events show AWS API errors

**Common Causes:**
1. **IAM Permissions**: Provider ServiceAccount lacks required permissions
   ```bash
   # Check provider logs
   kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=50
   ```

2. **Invalid ASN**: ASN must be in valid range (64512-65534 for private, 1-65534 for public)
   ```bash
   # Check resource status
   kubectl describe transitgateway dev-hub-tgw -n crossplane-system
   ```

3. **Region Issues**: Ensure region is consistent across resources
   ```bash
   # Verify region in spec
   kubectl get transitgateway dev-hub-tgw -n crossplane-system -o yaml | grep region
   ```

### VPC Attachment Fails

**Symptoms:**
- TransitGatewayAttachment stuck in "Provisioning"
- Events show "VPC not found" or "subnet not found"

**Common Causes:**
1. **Missing VPC Labels**: VPC doesn't have required labels for selector matching
   ```bash
   # Check VPC labels
   kubectl get vpc -n crossplane-system --show-labels
   ```

2. **No Matching Subnets**: No subnets found with tier: private label
   ```bash
   # Check subnet labels
   kubectl get subnet -n crossplane-system --show-labels
   ```

3. **Selector Mismatch**: Selector labels don't match any resources
   ```bash
   # Check attachment spec
   kubectl get transitgatewayattachment dev-vpc1-attachment -n crossplane-system -o yaml
   ```

**Resolution:**
```bash
# Add missing labels to VPC
kubectl label vpc <vpc-name> -n crossplane-system \
  portal-kombat.io/network-component=vpc \
  environment=dev

# Add tier label to subnets
kubectl label subnet <subnet-name> -n crossplane-system tier=private
```

### Route Table Not Associated

**Symptoms:**
- TransitGatewayRouteTable created but not associated with Transit Gateway
- Routes not being applied

**Common Causes:**
1. **Transit Gateway Not Ready**: Route table created before Transit Gateway is ready
   ```bash
   # Check Transit Gateway status
   kubectl get transitgateway -n crossplane-system
   ```

2. **Selector Mismatch**: Selector doesn't match Transit Gateway labels
   ```bash
   # Check Transit Gateway labels
   kubectl get transitgateway dev-hub-tgw -n crossplane-system --show-labels
   ```

**Resolution:**
```bash
# Wait for Transit Gateway to be ready
kubectl wait --for=condition=Ready transitgateway/dev-hub-tgw -n crossplane-system --timeout=300s

# Recreate route table
kubectl delete transitgatewayroutetable dev-isolated-rt -n crossplane-system
kubectl apply -f 03-tgw-with-route-table.yaml
```

## Best Practices

### Naming Conventions

- Use environment prefix: `dev-`, `staging-`, `prod-`
- Be descriptive: `hub-tgw` not `tgw1`
- Include purpose: `vpc1-attachment`, `isolated-rt`

### Tagging

Always include standard tags:
```yaml
tags:
  managedBy: Crossplane
  project: portal-kombat
  environment: dev
  # Additional custom tags as needed
```

### Selectors

Use consistent label patterns:
```yaml
# Good: Specific and maintainable
transitGatewaySelector:
  matchLabels:
    portal-kombat.io/network-component: transit-gateway
    environment: dev

# Bad: Too generic
transitGatewaySelector:
  matchLabels:
    type: tgw
```

### Resource Ordering

Deploy resources in this order:
1. Transit Gateway (hub)
2. VPC Attachments (spokes)
3. Route Tables (routing logic)

This ensures dependencies are met and reduces reconciliation errors.

## Next Steps

### Phase 2 Features (Coming Soon)

- Dynamic routing with BGP
- VPN attachments for on-premises connectivity
- Advanced routing policies
- Multi-region support

### Related Examples

- VPC examples: `examples/networking/phase1/`
- Security Group examples: `examples/security/`
- Complete infrastructure stacks: `environments/dev/infrastructure/`

## Additional Resources

- [Crossplane Documentation](https://docs.crossplane.io/)
- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [Portal Kombat Architecture](../../../docs/ARCHITECTURE.md)
- [AWS Routing Specification](../../../specs/aws-routing-composition/requirements.md)
