# ArgoCD + Crossplane Sync Issues Troubleshooting

## Problem: Application Shows OutOfSync with No Real Changes

When ArgoCD detects your Crossplane resources as "OutOfSync" even though the actual configuration hasn't changed, it's usually due to metadata or status fields that Crossplane manages.

## Root Causes

### 1. Status Fields
Crossplane continuously updates `.status` fields with reconciliation state. ArgoCD sees these as differences.

**Example:**
```yaml
status:
  conditions:
    - type: Ready
      status: "True"
      lastTransitionTime: "2025-01-15T10:30:00Z"  # Changes every reconcile
  atProvider:
    id: vpc-abc123
    arn: arn:aws:ec2:us-east-2:123456789:vpc/vpc-abc123
```

### 2. Crossplane Annotations
Crossplane controllers add annotations for tracking:

```yaml
metadata:
  annotations:
    crossplane.io/external-name: vpc-abc123        # Added by Crossplane
    crossplane.io/composition-resource-name: vpc   # Added by composition
```

### 3. Managed Fields
Kubernetes field managers track which controller owns which fields:

```yaml
metadata:
  managedFields:
    - manager: crossplane
      operation: Update
      time: "2025-01-15T10:30:00Z"
```

### 4. Resource References
Composite resources add references that aren't in Git:

```yaml
spec:
  resourceRefs:
    - apiVersion: ec2.aws.upbound.io/v1beta1
      kind: VPC
      name: dev-shared-vpc-xyz
```

### 5. Default Values
Providers and compositions inject defaults:

```yaml
spec:
  forProvider:
    region: us-east-2
    deletionPolicy: Delete  # Added if not specified
```

## Solution: Configure ignoreDifferences

The `ignoreDifferences` configuration tells ArgoCD which fields to ignore when comparing Git vs cluster state.

### Already Applied to Your Setup

Your `infrastructure-claims-apps.yaml` now includes:

```yaml
ignoreDifferences:
  # Ignore all status fields
  - group: "*"
    kind: "*"
    jsonPointers:
      - /status

  # Ignore Crossplane metadata annotations
  - group: "*"
    kind: "*"
    jqPathExpressions:
      - '.metadata.annotations["crossplane.io/external-name"]'
      - '.metadata.annotations["crossplane.io/composition-resource-name"]'
      - '.metadata.managedFields'

  # Ignore Crossplane composite resource fields
  - group: "*.plt.intelerad.io"
    kind: "*"
    jsonPointers:
      - /spec/resourceRefs
      - /spec/claimRef

  # Ignore fields managed by Crossplane providers
  - group: "*.aws.upbound.io"
    kind: "*"
    managedFieldsManagers:
      - crossplane
      - provider-aws-ec2
      - provider-aws-s3
      - provider-aws-rds
      - provider-aws-iam
```

## Verification Steps

### 1. Check ArgoCD Diff View

```bash
# Get detailed diff in CLI
argocd app diff dev-infrastructure-claims

# Or view in UI
# Navigate to: ArgoCD UI → Applications → dev-infrastructure-claims → APP DIFF
```

### 2. View Ignored Differences

ArgoCD UI will show ignored fields with a strikethrough:

```
status:  ← This line will be struck through in UI
  conditions: []
```

### 3. Force Sync to Test

```bash
# Sync the application
kubectl patch application dev-infrastructure-claims -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'

# Watch sync status
kubectl get application dev-infrastructure-claims -n argocd -w
```

### 4. Check Application Status

```bash
# Should show Synced + Healthy
kubectl get application dev-infrastructure-claims -n argocd

# Detailed status
kubectl describe application dev-infrastructure-claims -n argocd
```

## Advanced Debugging

### View Actual Differences

```bash
# Get the live resource
kubectl get vpcnetwork platform-prod-shared-vpc -o yaml > live.yaml

# Get the Git version (from your repo)
cat environments/prod/infrastructure/network/platform-prod-vpc.yaml > git.yaml

# Compare with diff tool
diff -u git.yaml live.yaml

# Or use yq for better YAML diff
yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' git.yaml live.yaml
```

### Check Specific Field Paths

```bash
# Check if a specific field is causing issues
kubectl get vpcnetwork platform-prod-shared-vpc -o jsonpath='{.status}'

# Check annotations
kubectl get vpcnetwork platform-prod-shared-vpc -o jsonpath='{.metadata.annotations}'

# Check resource references
kubectl get vpcnetwork platform-prod-shared-vpc -o jsonpath='{.spec.resourceRefs}'
```

## Additional ignoreDifferences Patterns

### Ignore Specific Fields by Name

```yaml
ignoreDifferences:
  - group: aws.plt.intelerad.io
    kind: VPCNetwork
    jsonPointers:
      - /spec/parameters/availabilityZones  # If order matters
```

### Ignore Entire Spec Section

```yaml
ignoreDifferences:
  - group: "*.aws.upbound.io"
    kind: "*"
    jsonPointers:
      - /spec/initProvider  # Ignore initial provider values
```

### Ignore by JQ Expression (More Flexible)

```yaml
ignoreDifferences:
  - group: "*"
    kind: "*"
    jqPathExpressions:
      - '.spec.forProvider.tags.CreatedAt'  # Ignore timestamp tags
```

## When to Use Different Strategies

### Use `jsonPointers` for:
- Exact field paths
- Known structure
- Simple field names
- Example: `/status`, `/spec/resourceRefs`

### Use `jqPathExpressions` for:
- Dynamic field names
- Complex queries
- Nested structures
- Example: `.metadata.annotations["crossplane.io/*"]`

### Use `managedFieldsManagers` for:
- Fields managed by specific controllers
- Broad ignore patterns
- Multiple providers
- Example: `crossplane`, `provider-aws-ec2`

## Testing Your Configuration

### 1. Apply the Updated ArgoCD Application

```bash
kubectl apply -f environments/dev/argocd/infrastructure-claims-apps.yaml
```

### 2. Wait for ArgoCD to Reconcile

```bash
# Watch for sync status to update
kubectl get application dev-infrastructure-claims -n argocd -w

# Should transition to: Synced + Healthy
```

### 3. Verify Ignored Fields

```bash
# Check if specific fields are being ignored
argocd app diff dev-infrastructure-claims --local-path=environments/dev/infrastructure
```

## Common Issues

### Issue: Still showing OutOfSync after adding ignoreDifferences

**Solution**: Add `RespectIgnoreDifferences=true` to syncOptions:

```yaml
syncOptions:
  - CreateNamespace=true
  - RespectIgnoreDifferences=true  # Required for ignoreDifferences to work
```

### Issue: Can't ignore fields with wildcards

**Solution**: Use `jqPathExpressions` instead of `jsonPointers`:

```yaml
# Won't work with jsonPointers
jsonPointers:
  - /metadata/annotations/crossplane.io/*

# Use jqPathExpressions instead
jqPathExpressions:
  - '.metadata.annotations | select(. != null) | keys[] | select(startswith("crossplane.io/"))'
```

### Issue: Ignore too broad, missing real changes

**Solution**: Be more specific with your ignore patterns:

```yaml
# Too broad - ignores ALL metadata
- group: "*"
  kind: "*"
  jsonPointers:
    - /metadata

# Better - only ignore specific metadata fields
- group: "*"
  kind: "*"
  jsonPointers:
    - /metadata/managedFields
    - /metadata/generation
```

## Best Practices

1. **Start Narrow**: Begin with specific ignore patterns, expand only if needed
2. **Test Before Production**: Test ignore patterns in dev environment first
3. **Document Why**: Add comments explaining why each field is ignored
4. **Monitor Sync Health**: Regularly check if applications stay synced
5. **Review Periodically**: Audit ignore patterns quarterly to ensure they're still needed

## References

- [ArgoCD Diffing Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/)
- [Crossplane Composition Documentation](https://docs.crossplane.io/latest/concepts/compositions/)
- [ArgoCD Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
