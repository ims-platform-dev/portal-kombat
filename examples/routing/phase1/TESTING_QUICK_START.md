# Phase 1 Integration Testing - Quick Start

## Quick Reference

This directory contains comprehensive integration testing for AWS Routing Composition Phase 1.

### Files

- `INTEGRATION_TESTING.md` - Comprehensive testing guide with manual procedures
- `run-integration-tests.sh` - Automated test execution script
- `cleanup-integration-tests.sh` - Automated cleanup script
- `01-transit-gateway.yaml` - Basic Transit Gateway example
- `02-tgw-with-attachment.yaml` - Transit Gateway with VPC Attachment
- `03-tgw-with-route-table.yaml` - Transit Gateway with Route Table

## Prerequisites

```bash
# 1. Active AWS SSO session
aws sso login --profile your-profile

# 2. Verify cluster access
kubectl cluster-info

# 3. Check Crossplane is healthy
kubectl get providers
```

## Quick Start

### Run All Tests

```bash
# Check prerequisites first (dry run)
./run-integration-tests.sh --dry-run

# Run all tests with verbose output
./run-integration-tests.sh --verbose
```

### Run Specific Test Case

```bash
# Test Case 1: Basic Transit Gateway
./run-integration-tests.sh --test-case 1

# Test Case 2: VPC Attachment
./run-integration-tests.sh --test-case 2

# Test Case 3: Route Table
./run-integration-tests.sh --test-case 3

# Test Case 4: End-to-End
./run-integration-tests.sh --test-case 4
```

## Cleanup

```bash
# Check what resources exist
./cleanup-integration-tests.sh --verify-only

# Interactive cleanup (with confirmation)
./cleanup-integration-tests.sh

# Automatic cleanup (no confirmation)
./cleanup-integration-tests.sh --force

# Check for orphaned AWS resources
./cleanup-integration-tests.sh --aws-cleanup
```

## Test Cases

| Test | Description | Duration |
|------|-------------|----------|
| 1 | Basic Transit Gateway | ~3 min |
| 2 | VPC Attachment with Subnet Selection | ~7 min |
| 3 | Route Table with Transit Gateway | ~2 min |
| 4 | End-to-End Provisioning | ~12 min |

## Expected Results

All tests should:
- ✅ Resources reach "Ready" status in Crossplane
- ✅ AWS resources visible in console/CLI
- ✅ Connection secrets created with correct values
- ✅ Selector-based binding works correctly

## Troubleshooting

### Tests Fail: "Cannot connect to cluster"
```bash
kubectl config current-context
# If wrong context, switch:
kubectl config use-context your-cluster-context
```

### Tests Fail: "AWS credentials not configured"
```bash
aws sso login --profile your-profile
# Verify:
aws sts get-caller-identity --region us-east-2
```

### Tests Fail: "No VPC found with required labels"
```bash
# Check VPCs
kubectl get vpc -n crossplane-system --show-labels

# VPC needs labels:
# - portal-kombat.io/network-component=vpc
# - environment=dev
```

### Tests Fail: "No private subnets found"
```bash
# Check subnets
kubectl get subnet -n crossplane-system -l tier=private

# Subnets need label: tier=private
```

### Resources Stuck in "Creating"
```bash
# Check provider logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-ec2 --tail=100

# Check resource events
kubectl describe transitgateway <name> -n crossplane-system
```

## Logs

Test logs are saved to:
- `test-run-YYYYMMDD-HHMMSS.log` - Test execution logs
- `cleanup-YYYYMMDD-HHMMSS.log` - Cleanup execution logs

## Manual Testing

For manual testing without automation, see `INTEGRATION_TESTING.md` for detailed step-by-step procedures.

## Support

For detailed troubleshooting, see:
- `INTEGRATION_TESTING.md` - Comprehensive troubleshooting guide
- `../../../platform/compositions/routing/` - Composition definitions
- `../../../platform/xrds/routing/` - XRD specifications
- `../../../docs/ARCHITECTURE.md` - Architecture documentation

## Test Coverage

Phase 1 integration tests cover:
- ✅ Transit Gateway provisioning
- ✅ VPC Attachment with selector-based binding
- ✅ Subnet tier selection (private subnets)
- ✅ Route Table creation
- ✅ Transit Gateway selector binding
- ✅ Connection secret generation
- ✅ AWS resource verification
- ✅ Multi-AZ subnet distribution
- ✅ Dependency ordering
- ✅ Resource cleanup

Not covered (future phases):
- ⏳ BGP routing (Phase 2)
- ⏳ Route propagation (Phase 2)
- ⏳ Inter-region peering (Phase 2)
- ⏳ VPN connections (Phase 2)
- ⏳ Direct Connect integration (Phase 3)

## Next Steps

After successful Phase 1 testing:
1. Document test results
2. Review Phase 2 specification
3. Plan Phase 2 implementation
4. Consider production readiness requirements
