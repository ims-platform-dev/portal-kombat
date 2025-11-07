# VPC Composition Troubleshooting Guide

This document tracks the systematic debugging and fixing of the `vpc-standard` Crossplane composition for VPC provisioning.

## Overview

The `vpc-standard` composition (`infra-definitions/compositions/network/vpc-standard.yaml`) had multiple syntax errors preventing successful VPC provisioning through the Port.io → GitHub → ArgoCD → EKS/Crossplane workflow.

## Issue Timeline and Fixes

### Issue #1: Invalid `patchSets:` Field Syntax ✅ FIXED

**Error Message:**
```
cannot compose resources: pipeline step "vpc-core" returned a fatal result:
cannot get Function input: cannot unmarshal JSON: unknown name "patchSets"
```

**Root Cause:**
Resources were using an invalid `patchSets:` field at the resource level instead of using `patches:` array with `type: PatchSet` references.

**Incorrect Syntax:**
```yaml
resources:
  - name: vpc
    patchSets:              # ❌ INVALID - patchSets is not a valid resource-level field
      - provider-config
      - region
    base:
      apiVersion: ec2.aws.upbound.io/v1beta1
      kind: VPC
```

**Correct Syntax:**
```yaml
resources:
  - name: vpc
    patches:                # ✅ CORRECT - use patches array
      - type: PatchSet      # ✅ Reference patchSet by type
        patchSetName: provider-config
      - type: PatchSet
        patchSetName: region
    base:
      apiVersion: ec2.aws.upbound.io/v1beta1
      kind: VPC
```

**Fix Applied:**
- Created `scripts/fix-patchsets-syntax.py` to systematically convert all 20+ resource definitions
- Fixed regex bug to handle hyphenated names (e.g., `provider-config`)
- Committed in: `commit dce723b` (2025-11-07)

**Reference:**
- Crossplane function-patch-and-transform v0.9.1 documentation
- Top-level `patchSets:` (lines 25-62) defines reusable patch configurations
- Resource-level must use `patches:` with `type: PatchSet` to reference them

---

### Issue #2: Invalid `policy.toFieldPath: Optional` ✅ FIXED

**Error Message:**
```
invalid Function input: resources[0].patches[4].policy.toFieldPathPolicy:
Invalid value: "Optional": unknown toFieldPathPolicy
```

**Root Cause:**
18 occurrences of `policy.toFieldPath: Optional` in the composition. The value `Optional` is only valid for `policy.fromFieldPath`, not `policy.toFieldPath`.

**Incorrect Usage:**
```yaml
patches:
  - type: ToCompositeFieldPath
    fromFieldPath: status.atProvider.id
    toFieldPath: status.vpcId
    policy:
      toFieldPath: Optional    # ❌ INVALID - Optional is not valid for toFieldPath
```

**Valid Policy Options:**
```yaml
# For fromFieldPath policy:
policy:
  fromFieldPath: Optional    # ✅ Valid - field is optional
  fromFieldPath: Required    # ✅ Valid - field is required

# For toFieldPath policy (merge strategies only):
policy:
  toFieldPath: MergeObjects            # ✅ Valid - merge object fields
  toFieldPath: MergeObjectsAppendArrays  # ✅ Valid - merge and append arrays
```

**Fix Applied:**
- Created `scripts/fix-tofieldpath-policy.py` to remove all 18 invalid declarations
- Removed both the `policy:` line and the `toFieldPath: Optional` line
- Found at lines: 106, 124, 142, 160, 178, 237, 340, 409, 478, 547, 616, 685, 743, 889, 1035, 1239, 1541, 1645
- Committed in: `commit dce723b` (2025-11-07)

**Reference:**
- Crossplane patch policies documentation
- `Optional` value is ONLY for `fromFieldPath` to handle missing source fields
- `toFieldPath` policies are for merge strategies when target is an object/map

---

### Issue #3: Non-Existent `InternetGatewayAttachment` Resource ✅ FIXED

**Error Message:**
```
cannot compose resources: cannot get existing composed resources:
cannot get composed resource: no matches for kind "InternetGatewayAttachment"
in version "ec2.aws.upbound.io/v1beta1"
```

**Root Cause:**
The composition tried to create an `InternetGatewayAttachment` resource, which doesn't exist in the Upbound AWS provider. In the Upbound provider, attaching an Internet Gateway to a VPC is done through the `InternetGateway` resource itself using a `vpcIdSelector` field.

**Incorrect Approach:**
```yaml
- name: internet-gateway
  base:
    apiVersion: ec2.aws.upbound.io/v1beta1
    kind: InternetGateway
    spec:
      forProvider:
        region: us-east-2
        # ❌ No VPC attachment here

- name: internet-gateway-attachment    # ❌ This resource type doesn't exist!
  base:
    apiVersion: ec2.aws.upbound.io/v1beta1
    kind: InternetGatewayAttachment    # ❌ Not a valid kind
    spec:
      forProvider:
        internetGatewayIdSelector: ...
        vpcIdSelector: ...
```

**Correct Approach:**
```yaml
- name: internet-gateway
  base:
    apiVersion: ec2.aws.upbound.io/v1beta1
    kind: InternetGateway
    spec:
      forProvider:
        region: us-east-2
        vpcIdSelector:          # ✅ Attach directly via selector
          matchControllerRef: true
          matchLabels:
            portal-kombat.io/network-component: vpc
```

**Fix Applied:**
- Removed entire `internet-gateway-attachment` resource definition (30 lines)
- Added `vpcIdSelector` to the `InternetGateway` resource
- Committed in: `commit f4f3737` (2025-11-07)

**Additional Note:**
After applying this fix, existing VPC claims needed to be deleted and recreated because the composite resource had cached references to the old non-existent `InternetGatewayAttachment` resources in its `spec.resourceRefs` array.

**Reference:**
- `kubectl explain internetgateways.ec2.aws.upbound.io.spec.forProvider`
- Upbound AWS provider documentation

---

### Issue #4: Invalid Label Selector Syntax (matchLabels) 🔄 IN PROGRESS

**Error Message:**
```
.spec.forProvider.routeTableIdSelector.matchLabels.portal-kombat: expected string,
got &value.valueUnstructured{Value:map[string]interface {}{
  "io/network-route-table-name":"dev-shared-public-a-public-rt"
}}
```

**Root Cause:**
The composition uses dot notation for label keys in `toFieldPath` which causes Crossplane to interpret them as nested maps instead of flat label keys.

**Incorrect Syntax:**
```yaml
patches:
  - type: FromCompositeFieldPath
    fromFieldPath: spec.parameters.publicSubnets[0].name
    toFieldPath: spec.forProvider.routeTableIdSelector.matchLabels.portal-kombat.io/network-route-table-name
    # ❌ This is interpreted as nested maps:
    #    matchLabels.portal-kombat -> map["io/network-route-table-name"]
```

**Correct Syntax:**
```yaml
patches:
  - type: FromCompositeFieldPath
    fromFieldPath: spec.parameters.publicSubnets[0].name
    toFieldPath: spec.forProvider.routeTableIdSelector.matchLabels[portal-kombat.io/network-route-table-name]
    # ✅ Bracket notation treats the full key as a single string
```

**Affected Patterns:**
The issue occurs in multiple resources:
- Route table associations (`routeTableIdSelector` and `subnetIdSelector`)
- Routes (`routeTableIdSelector`)

**Locations Found:**
Lines with dot notation that need bracket notation:
- Line 731: `matchLabels.portal-kombat.io/network-route-table-name`
- Line 772: `matchLabels.portal-kombat.io/network-route-table-name`
- Line 875: `matchLabels.portal-kombat.io/network-route-table-name`
- Line 916: `matchLabels.portal-kombat.io/network-route-table-name`
- Multiple similar occurrences for subnet selectors

**Fix Status:**
🔄 **IN PROGRESS** - Need to create systematic fix script

**Fix Plan:**
1. Create `scripts/fix-matchlabels-bracket-notation.py`
2. Convert all `matchLabels.portal-kombat.io/network-*` patterns to bracket notation
3. Apply to both `routeTableIdSelector` and `subnetIdSelector` patches
4. Test VPC provisioning after fix

**Reference:**
- Crossplane patch field path documentation
- Kubernetes label naming conventions (slashes and dots require bracket notation)

---

## Testing and Validation

### Current Status

**Fixed Issues:**
- ✅ patchSets syntax (Issue #1)
- ✅ toFieldPath policy (Issue #2)
- ✅ InternetGatewayAttachment (Issue #3)

**In Progress:**
- 🔄 matchLabels bracket notation (Issue #4)

**Pending:**
- ⏳ VPC provisioning end-to-end test
- ⏳ ArgoCD sync resolution verification

### Validation Commands

```bash
# Check XVPCNetwork composite status
kubectl get xvpcnetwork.aws.plt.intelerad.io -o wide

# Check VPC claim status
kubectl get vpcnetwork dev-shared-vpc -n default

# Check detailed composite events
kubectl describe xvpcnetwork.aws.plt.intelerad.io <name>

# Check composition revisions
kubectl get compositionrevisions.apiextensions.crossplane.io | grep vpc-standard

# Trigger ArgoCD sync
kubectl patch application dev-crossplane-platform -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Check ArgoCD application status
kubectl get application dev-infrastructure-claims -n argocd
```

### Expected Outcome

After all fixes are applied:
- ✅ XVPCNetwork composite shows `SYNCED=True` and `READY=True`
- ✅ VPCNetwork claim shows `SYNCED=True` and `READY=True`
- ✅ All AWS resources (VPC, subnets, route tables, IGW, NAT gateway) are created
- ✅ ArgoCD application `dev-infrastructure-claims` shows `Synced` and `Healthy`

---

## Lessons Learned

### 1. Composition Syntax Validation

**Problem:** Multiple syntax errors in a large (1600+ line) composition file.

**Solution:**
- Use `kubectl apply --dry-run=client` to catch basic syntax errors
- Test compositions in dev environment before promoting
- Create smaller, focused compositions for easier debugging
- Use composition validation tools (e.g., `crossplane beta validate`)

### 2. Crossplane Resource Caching

**Problem:** After fixing composition, Crossplane still tried to reconcile old cached resources.

**Solution:**
- Delete and recreate claims to force fresh reconciliation
- Use `compositionUpdatePolicy: Automatic` to auto-update to latest revision
- Check `spec.resourceRefs` on composite resources for stale references

### 3. Provider API Differences

**Problem:** Assumed AWS provider would have separate attachment resources like native AWS API.

**Solution:**
- Always check provider documentation: `kubectl explain <resource>.spec.forProvider`
- Use `kubectl api-resources | grep <provider>` to discover available types
- Upbound providers may differ from official Crossplane providers

### 4. Label Key Naming in Patches

**Problem:** Label keys with dots and slashes require special syntax in patch field paths.

**Solution:**
- Use bracket notation for label keys: `matchLabels[full.label/key]`
- Dot notation only works for simple field names without special characters
- Test patches with complex label keys in isolation

---

## Related Documentation

- [Crossplane Compositions Documentation](https://docs.crossplane.io/latest/concepts/compositions/)
- [function-patch-and-transform Reference](https://docs.crossplane.io/latest/concepts/patch-and-transform/)
- [Upbound AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-aws/)
- [Port.io Integration Guide](./README.md)

---

## Contributing

When encountering new composition issues:

1. Document the error message exactly
2. Identify the root cause through kubectl commands
3. Create a focused fix script if systematic changes are needed
4. Test the fix in dev environment
5. Update this troubleshooting guide with findings
6. Commit changes with detailed commit messages

---

**Last Updated:** 2025-11-07
**Status:** Active Debugging - Issue #4 In Progress
