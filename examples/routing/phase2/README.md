# Phase 2: Advanced AWS Transit Gateway Routing Examples

This directory contains advanced routing examples demonstrating **route propagation**, **traffic segmentation**, and **hub-and-spoke topologies** using Crossplane compositions.

## Overview

Phase 2 introduces:
- **Route Propagation**: Automatic route learning from VPC attachments
- **Route Table Associations**: Controlling which route table an attachment uses
- **Traffic Segmentation**: Isolating environments using separate route tables
- **Dynamic Routing**: Selector-based resource binding for flexible configurations

## Prerequisites

Before running these examples:

1. **Crossplane Installed**: Ensure Crossplane is running in your cluster
2. **AWS Provider Configured**: Provider authentication (IRSA) set up
3. **XRDs and Compositions Deployed**:
   ```bash
   kubectl get xrd xtransitgateways.aws.plt.intelerad.io
   kubectl get xrd xtransitgatewayattachments.aws.plt.intelerad.io
   kubectl get xrd xtransitgatewayroutetables.aws.plt.intelerad.io
   kubectl get compositions | grep transit-gateway
   ```
4. **Existing VPCs**: You need VPC IDs and subnet IDs (or use VPC compositions)
5. **AWS Region**: Examples use `us-east-2` (update if using different region)

## Examples

### Example 1: Route Propagation (`01-route-propagation.yaml`)

**Concept**: Automatic route learning from VPC attachments without static route configuration.

**What It Does**:
- Creates Transit Gateway
- Attaches two VPCs (app1, app2)
- Creates route table with propagation enabled for both attachments
- Routes from both VPCs automatically appear in the route table

**Key Features**:
- Selector-based Transit Gateway binding (`transitGatewaySelector`)
- Attachment selectors in route propagation configuration
- Dynamic route discovery (no manual route entries)

**When To Use**:
- Dynamic environments where VPC CIDRs change
- Multiple VPCs need to communicate freely
- Simplified route management

**Traffic Flow**:
```
App1 VPC ←→ Transit Gateway Route Table ←→ App2 VPC
         (routes automatically propagated)
```

**Deploy**:
```bash
# Update VPC IDs and subnet IDs in the file first
kubectl apply -f 01-route-propagation.yaml

# Check status
kubectl get transitgatewayroutetable route-propagation-shared-rt -o yaml
# Look for status.propagatedAttachments[]
```

---

### Example 2: Segmented Routing (`02-segmented-routing.yaml`)

**Concept**: Traffic isolation between production and non-production environments using separate route tables.

**What It Does**:
- Creates Transit Gateway with default associations/propagations disabled
- Attaches production VPC and non-production VPC
- Creates two isolated route tables (prod-rt, nonprod-rt)
- Each route table only propagates routes from its environment

**Key Features**:
- Environment-based label selectors
- Isolated routing domains
- Production traffic cannot reach non-production (and vice versa)

**When To Use**:
- Compliance requirements (SOC 2, PCI DSS, HIPAA)
- Blast radius containment
- Environment isolation policies
- Independent scaling and testing

**Traffic Flow**:
```
Production VPC → prod-rt (only prod routes) → Production VPC
                    ↕
            Transit Gateway
                    ↕
Non-Prod VPC → nonprod-rt (only nonprod routes) → Non-Prod VPC

❌ Production VPC ⤫ Non-Production VPC (no route exists)
```

**Security Benefits**:
- Data exfiltration prevention
- Testing isolation (prevent prod data leaks)
- Change blast radius containment
- Regulatory compliance

**Deploy**:
```bash
# Update VPC IDs and subnet IDs in the file first
kubectl apply -f 02-segmented-routing.yaml

# Verify isolation
kubectl describe transitgatewayroutetable segmented-prod-rt
kubectl describe transitgatewayroutetable segmented-nonprod-rt
```

---

### Example 3: Shared Services VPC (`03-shared-services.yaml`)

**Concept**: Hub-and-spoke topology with centralized shared services accessible to all spoke VPCs.

**What It Does**:
- Creates Transit Gateway
- Attaches shared services VPC (hub)
- Attaches two spoke VPCs (spoke1, spoke2)
- Creates hub route table (bidirectional: hub ←→ all spokes)
- Creates spoke route table (unidirectional: spokes → hub only)

**Key Features**:
- Role-based label selectors (`role: hub`, `role: spoke`)
- Asymmetric routing (hub sees all spokes, spokes only see hub)
- Spoke-to-spoke traffic blocked by default

**When To Use**:
- Centralized DNS, monitoring, logging services
- Shared Active Directory / LDAP
- Common security services (IDS/IPS)
- Centralized NAT Gateway for internet egress
- Shared data services (databases, caching)

**Traffic Flow**:
```
Spoke 1 VPC ─┐
             ├─→ Spoke RT (hub routes only) ─→ Shared Services VPC
Spoke 2 VPC ─┘                                        │
                                                      ↓
                                              Hub RT (all spoke routes)
                                                      ↓
                                          Can reach all spokes

❌ Spoke 1 VPC ⤫ Spoke 2 VPC (no direct route)
```

**Common Services**:
- DNS Resolver (Route 53 Resolver endpoints)
- NTP servers
- Centralized logging (CloudWatch, Elasticsearch)
- Security scanning (Qualys, Nessus)
- Shared NAT Gateways
- Active Directory domain controllers

**Deploy**:
```bash
# Update VPC IDs and subnet IDs in the file first
kubectl apply -f 03-shared-services.yaml

# Verify hub can reach spokes
kubectl describe transitgatewayroutetable shared-services-hub-rt

# Verify spokes can only reach hub
kubectl describe transitgatewayroutetable shared-services-spoke-rt
```

---

## Core Concepts

### Route Propagation

Route propagation enables **automatic route learning** from Transit Gateway attachments.

**How It Works**:
1. VPC is attached to Transit Gateway
2. VPC CIDR is automatically advertised to specified route tables
3. Route tables with propagation enabled learn the CIDR
4. Traffic to that CIDR is routed to the VPC attachment

**Configuration**:
```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: TransitGatewayRouteTable
spec:
  parameters:
    routePropagations:
      # Direct attachment ID
      - attachmentId: tgw-attach-0123456789abcdef0

      # Or use selector (preferred for dynamic environments)
      - attachmentSelector:
          matchLabels:
            portal-kombat.io/environment: production
            portal-kombat.io/vpc: app1
```

**Status Field**:
```yaml
status:
  propagatedAttachments:
    - attachmentId: tgw-attach-0123456789abcdef0
      state: enabled
    - attachmentId: tgw-attach-0123456789abcdef1
      state: enabled
```

---

### Route Table Associations

Route table associations control **which route table an attachment uses** for routing decisions.

**How It Works**:
1. Attachment is created (VPC attached to Transit Gateway)
2. Route table association binds attachment to a specific route table
3. Traffic from the VPC uses only that route table's routes
4. Enables traffic segmentation and isolation

**Configuration**:
```yaml
apiVersion: aws.plt.intelerad.io/v1alpha1
kind: TransitGatewayAttachment
spec:
  parameters:
    routeTableIds:
      - tgw-rtb-0123456789abcdef0  # Associate with this route table
      - tgw-rtb-0123456789abcdef1  # Can associate with multiple
```

**Status Field**:
```yaml
status:
  associatedRouteTableIds:
    - tgw-rtb-0123456789abcdef0
    - tgw-rtb-0123456789abcdef1
```

---

### Selector-Based Resource Binding

Crossplane selectors enable **dynamic resource binding** using Kubernetes labels.

**Direct ID Binding** (Static):
```yaml
spec:
  parameters:
    transitGatewayId: tgw-0123456789abcdef0  # Hard-coded ID
    vpcId: vpc-0123456789abcdef0
```

**Selector Binding** (Dynamic):
```yaml
spec:
  parameters:
    transitGatewaySelector:
      matchLabels:
        portal-kombat.io/environment: production
        portal-kombat.io/region: us-east-2
    vpcIdSelector:
      matchLabels:
        portal-kombat.io/purpose: application
      matchControllerRef: true  # Match VPC created by same composite
```

**Benefits**:
- Decouples resource IDs from configuration
- Enables GitOps workflows (no hard-coded IDs)
- Supports dynamic environments
- Simplifies multi-region deployments

---

## Traffic Patterns

### Full Mesh (All-to-All)
All VPCs can communicate with each other.

**Configuration**:
- Single route table
- All attachments propagate to the route table
- All attachments associated with the route table

**Use Case**: Development environments, small-scale deployments

---

### Hub-and-Spoke
Centralized hub, spokes communicate through hub.

**Configuration**:
- Hub route table: learns routes from all spokes
- Spoke route table: learns routes from hub only
- Hub associated with hub-rt, spokes associated with spoke-rt

**Use Case**: Shared services, centralized security

---

### Segmented Isolation
Environments completely isolated from each other.

**Configuration**:
- Separate route table per environment
- Each route table only propagates its environment's routes
- Attachments associated with environment-specific route tables

**Use Case**: Production/non-production isolation, regulatory compliance

---

### Hybrid (Partial Mesh)
Some VPCs communicate directly, others isolated.

**Configuration**:
- Multiple route tables with selective propagations
- Strategic route table associations
- Mix of propagation and static routes

**Use Case**: Complex enterprise architectures, security zones

---

## Best Practices

### 1. Use Selectors Over Direct IDs
```yaml
# ✅ Good: Selector-based (flexible, GitOps-friendly)
transitGatewaySelector:
  matchLabels:
    portal-kombat.io/environment: production

# ❌ Avoid: Hard-coded IDs (brittle, not reusable)
transitGatewayId: tgw-0123456789abcdef0
```

### 2. Label Your Resources Consistently
```yaml
metadata:
  labels:
    portal-kombat.io/environment: production
    portal-kombat.io/tier: application
    portal-kombat.io/team: platform-engineering
    portal-kombat.io/purpose: user-workloads
```

### 3. Disable Default Route Tables
```yaml
spec:
  parameters:
    defaultRouteTableAssociation: false
    defaultRouteTablePropagation: false
```
This gives you **explicit control** over routing topology.

### 4. Document Traffic Flows
Include traffic flow comments in your YAML:
```yaml
# Traffic Flow:
# ✅ Spoke 1 → Hub: ALLOWED
# ❌ Spoke 1 → Spoke 2: BLOCKED
```

### 5. Test Connectivity
Always verify traffic flows after deployment:
```bash
# Test from spoke1 to hub (should succeed)
# Test from spoke1 to spoke2 (should fail)
```

### 6. Use ArgoCD Sync Waves for Ordering
```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # Transit Gateway first
    argocd.argoproj.io/sync-wave: "2"  # Attachments second
    argocd.argoproj.io/sync-wave: "3"  # Route tables third
```

---

## Troubleshooting

### Route Propagation Not Working

**Symptoms**: Routes not appearing in route table

**Checks**:
```bash
# 1. Check attachment status
kubectl describe transitgatewayattachment <name>
# Look for state: "available"

# 2. Check propagation status
kubectl describe transitgatewayroutetable <name>
# Look for status.propagatedAttachments[]

# 3. Verify in AWS
aws ec2 get-transit-gateway-route-table-propagations \
  --transit-gateway-route-table-id <rt-id> \
  --region us-east-2
```

**Common Causes**:
- Attachment not ready (state != available)
- Selector doesn't match any attachments
- Route table not associated with attachment
- AWS API propagation delay (wait 30-60 seconds)

---

### Route Table Association Not Created

**Symptoms**: Association doesn't appear in attachment status

**Checks**:
```bash
# 1. Check attachment status
kubectl get transitgatewayattachment <name> -o jsonpath='{.status.associatedRouteTableIds}'

# 2. Check if routeTableIds was provided
kubectl get transitgatewayattachment <name> -o jsonpath='{.spec.parameters.routeTableIds}'

# 3. Verify route table exists
kubectl get transitgatewayroutetable <name>
```

**Common Causes**:
- routeTableIds not specified in attachment spec
- Route table ID doesn't exist yet (order of creation)
- Route table not in ready state
- AWS API rate limiting

---

### Connectivity Between VPCs Fails

**Symptoms**: Cannot ping/connect between VPCs

**Checks**:
```bash
# 1. Verify routes exist
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <rt-id> \
  --filters "Name=state,Values=active" \
  --region us-east-2

# 2. Check route table associations
kubectl describe transitgatewayattachment <name>
# Verify associatedRouteTableIds matches expected

# 3. Check VPC route tables (local VPC routing)
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --region us-east-2
# Ensure routes to Transit Gateway exist
```

**Common Causes**:
- Missing route propagation configuration
- Wrong route table association
- VPC route table missing route to Transit Gateway
- Security group blocking traffic
- Network ACL blocking traffic
- Attachment not in "available" state

---

## Validation Commands

### Check All Resources
```bash
kubectl get transitgateway,transitgatewayattachment,transitgatewayroutetable \
  -l portal-kombat.io/demo=true
```

### Verify Route Propagations
```bash
kubectl describe transitgatewayroutetable <name>
# Check: status.propagatedAttachments[]
```

### Verify Route Table Associations
```bash
kubectl describe transitgatewayattachment <name>
# Check: status.associatedRouteTableIds[]
```

### Check AWS Resources
```bash
# Transit Gateway
aws ec2 describe-transit-gateways \
  --filters "Name=tag:example,Values=<example-name>" \
  --region us-east-2

# Attachments
aws ec2 describe-transit-gateway-attachments \
  --filters "Name=transit-gateway-id,Values=<tgw-id>" \
  --region us-east-2

# Route Tables
aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=<tgw-id>" \
  --region us-east-2

# Routes
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id <rt-id> \
  --filters "Name=type,Values=propagated" \
  --region us-east-2
```

---

## Cleanup

To remove example resources:

```bash
# Delete specific example
kubectl delete -f 01-route-propagation.yaml
kubectl delete -f 02-segmented-routing.yaml
kubectl delete -f 03-shared-services.yaml

# Or delete all demo resources
kubectl delete transitgateway,transitgatewayattachment,transitgatewayroutetable \
  -l portal-kombat.io/demo=true
```

**Important**: Crossplane will delete the AWS resources automatically, but this may take several minutes. Monitor with:

```bash
kubectl get transitgateway,transitgatewayattachment,transitgatewayroutetable \
  -l portal-kombat.io/demo=true -w
```

---

## Next Steps

1. **Customize Examples**: Update VPC IDs, subnet IDs, and CIDRs for your environment
2. **Test Connectivity**: Verify traffic flows using ping, curl, or network testing tools
3. **Monitor Status**: Use `kubectl describe` to check propagation and association status
4. **AWS Verification**: Confirm routes and associations in AWS console
5. **Integration Testing**: Run automated tests from `examples/routing/phase2/tests/` (if available)

---

## Additional Resources

- [AWS Transit Gateway Documentation](https://docs.aws.amazon.com/vpc/latest/tgw/)
- [Crossplane Composition Documentation](https://docs.crossplane.io/latest/concepts/compositions/)
- [Portal Kombat Architecture Docs](../../../docs/ARCHITECTURE.md)
- [Transit Gateway Best Practices](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-best-design-practices.html)
