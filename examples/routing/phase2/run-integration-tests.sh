#!/bin/bash
set -euo pipefail

################################################################################
# Phase 2 Integration Test Automation Script
#
# This script automates integration testing for AWS Routing Composition Phase 2.
# It tests VPC with Transit Gateway routing, validating label propagation and
# route creation from VPC private subnets to Transit Gateway.
#
# Usage:
#   ./run-integration-tests.sh                    # Run all tests
#   ./run-integration-tests.sh --test-case 1      # Run specific test case
#   ./run-integration-tests.sh --verbose          # Verbose output
#   ./run-integration-tests.sh --dry-run          # Validate without applying
#
# Prerequisites:
#   - kubectl configured for dev cluster
#   - AWS CLI configured with appropriate credentials (AWS_PROFILE=ims-platform-dev)
#   - Phase 1 Transit Gateway XRD and composition deployed
#   - Phase 2 VPC composition with Transit Gateway routing deployed
#
################################################################################

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="default"
CROSSPLANE_NAMESPACE="crossplane-system"
REGION="us-east-2"
TIMEOUT_TGW=300         # 5 minutes for Transit Gateway
TIMEOUT_VPC=600         # 10 minutes for VPC (complex resource)
TIMEOUT_ATTACHMENT=600  # 10 minutes for VPC Attachment
TIMEOUT_ROUTES=300      # 5 minutes for routes to propagate
VERBOSE=false
DRY_RUN=false
TEST_CASE=""
LOG_FILE="${SCRIPT_DIR}/test-run-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$*"
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}ℹ ${NC}$*"
    fi
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅${NC} $*"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌${NC} $*" >&2
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠️ ${NC}$*"
}

log_step() {
    log "STEP" "$*"
    echo -e "${BLUE}▶${NC} $*"
}

print_header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$*"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "HEADER" "$*"
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

OPTIONS:
    --test-case N     Run specific test case (1-2)
    --verbose         Enable verbose output
    --dry-run         Validate prerequisites without applying resources
    --help            Display this help message

TEST CASES:
    1. VPC with Transit Gateway Routing
    2. End-to-End Connectivity Validation

EXAMPLES:
    $(basename "$0")                    # Run all tests
    $(basename "$0") --test-case 1      # Run test case 1 only
    $(basename "$0") --verbose          # Verbose output for all tests
    $(basename "$0") --dry-run          # Check prerequisites only

EOF
    exit 0
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    local prereq_failed=false

    # Check kubectl
    log_step "Checking kubectl..."
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install kubectl."
        prereq_failed=true
    else
        log_success "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    fi

    # Check AWS CLI
    log_step "Checking AWS CLI..."
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not found. Please install AWS CLI."
        prereq_failed=true
    else
        log_success "AWS CLI found: $(aws --version)"
    fi

    # Check cluster connectivity
    log_step "Checking cluster connectivity..."
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Check kubectl context."
        prereq_failed=true
    else
        log_success "Cluster connected: $(kubectl config current-context)"
    fi

    # Check AWS credentials
    log_step "Checking AWS credentials..."
    if ! AWS_PROFILE=ims-platform-dev aws sts get-caller-identity --region "$REGION" &> /dev/null; then
        log_error "AWS credentials not configured or expired. Run 'aws sso login --profile ims-platform-dev'."
        prereq_failed=true
    else
        local account=$(AWS_PROFILE=ims-platform-dev aws sts get-caller-identity --region "$REGION" --query 'Account' --output text)
        log_success "AWS authenticated: Account $account (profile: ims-platform-dev)"
    fi

    # Check Crossplane providers
    log_step "Checking Crossplane providers..."
    if ! kubectl get providers -n "$CROSSPLANE_NAMESPACE" &> /dev/null; then
        log_error "Cannot access Crossplane providers. Check Crossplane installation."
        prereq_failed=true
    else
        local unhealthy=$(kubectl get providers -n "$CROSSPLANE_NAMESPACE" -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Healthy" and .status!="True")) | .metadata.name')
        if [ -n "$unhealthy" ]; then
            log_error "Unhealthy providers found: $unhealthy"
            prereq_failed=true
        else
            log_success "All Crossplane providers healthy"
        fi
    fi

    # Check XRD existence
    log_step "Checking XRDs..."
    if ! kubectl get xrd xvpcnetworks.aws.plt.intelerad.io &> /dev/null; then
        log_error "VPCNetwork XRD not found. Deploy platform XRDs first."
        prereq_failed=true
    else
        log_success "VPCNetwork XRD found"
    fi

    if ! kubectl get xrd xtransitgateways.aws.plt.intelerad.io &> /dev/null; then
        log_error "TransitGateway XRD not found. Deploy platform XRDs first."
        prereq_failed=true
    else
        log_success "TransitGateway XRD found"
    fi

    if ! kubectl get xrd xtransitgatewayattachments.aws.plt.intelerad.io &> /dev/null; then
        log_error "TransitGatewayAttachment XRD not found. Deploy platform XRDs first."
        prereq_failed=true
    else
        log_success "TransitGatewayAttachment XRD found"
    fi

    # Check compositions
    log_step "Checking Compositions..."
    if ! kubectl get composition vpc-standard &> /dev/null; then
        log_error "vpc-standard composition not found. Deploy platform compositions first."
        prereq_failed=true
    else
        log_success "vpc-standard composition found"
    fi

    if ! kubectl get composition transit-gateway-standard &> /dev/null; then
        log_error "transit-gateway-standard composition not found. Deploy platform compositions first."
        prereq_failed=true
    else
        log_success "transit-gateway-standard composition found"
    fi

    if [ "$prereq_failed" = true ]; then
        log_error "Prerequisites check failed. Please resolve issues above."
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local timeout=$3
    local namespace=${4:-$NAMESPACE}

    log_step "Waiting for $resource_type/$resource_name to become Ready (timeout: ${timeout}s)..."

    if kubectl wait --for=condition=Ready "$resource_type/$resource_name" \
        -n "$namespace" --timeout="${timeout}s" >> "$LOG_FILE" 2>&1; then
        log_success "$resource_type/$resource_name is Ready"
        return 0
    else
        log_error "$resource_type/$resource_name did not become Ready within ${timeout}s"
        log_info "Resource status:"
        kubectl get "$resource_type/$resource_name" -n "$namespace" -o yaml | tee -a "$LOG_FILE"
        return 1
    fi
}

get_resource_status() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$NAMESPACE}

    kubectl get "$resource_type/$resource_name" -n "$namespace" -o json 2>/dev/null
}

verify_connection_secret() {
    local secret_name=$1
    local namespace=${2:-$NAMESPACE}

    log_step "Verifying connection secret: $secret_name..."

    if ! kubectl get secret "$secret_name" -n "$namespace" &> /dev/null; then
        log_error "Connection secret $secret_name not found"
        return 1
    fi

    log_success "Connection secret $secret_name exists"

    if [ "$VERBOSE" = true ]; then
        log_info "Secret keys:"
        kubectl get secret "$secret_name" -n "$namespace" -o jsonpath='{.data}' | \
            jq -r 'keys[]' | sed 's/^/  - /' | tee -a "$LOG_FILE"
    fi

    return 0
}

verify_aws_vpc() {
    local vpc_id=$1

    log_step "Verifying AWS VPC: $vpc_id..."

    if AWS_PROFILE=ims-platform-dev aws ec2 describe-vpcs \
        --vpc-ids "$vpc_id" \
        --region "$REGION" &> /dev/null; then
        log_success "AWS VPC $vpc_id exists"

        if [ "$VERBOSE" = true ]; then
            AWS_PROFILE=ims-platform-dev aws ec2 describe-vpcs \
                --vpc-ids "$vpc_id" \
                --region "$REGION" \
                --query 'Vpcs[0].[State,CidrBlock]' \
                --output table | tee -a "$LOG_FILE"
        fi
        return 0
    fi

    log_error "AWS VPC $vpc_id not found or not accessible"
    return 1
}

verify_transit_gateway_routes() {
    local route_table_id=$1
    local destination_cidr=$2

    log_step "Verifying Transit Gateway route in route table $route_table_id for $destination_cidr..."

    local route_exists=$(AWS_PROFILE=ims-platform-dev aws ec2 describe-route-tables \
        --route-table-ids "$route_table_id" \
        --region "$REGION" \
        --query "RouteTables[0].Routes[?DestinationCidrBlock=='$destination_cidr' && TransitGatewayId!=null] | length(@)" \
        --output text 2>/dev/null)

    if [ "$route_exists" -gt 0 ]; then
        log_success "Transit Gateway route found for $destination_cidr"

        if [ "$VERBOSE" = true ]; then
            AWS_PROFILE=ims-platform-dev aws ec2 describe-route-tables \
                --route-table-ids "$route_table_id" \
                --region "$REGION" \
                --query "RouteTables[0].Routes[?DestinationCidrBlock=='$destination_cidr']" \
                --output table | tee -a "$LOG_FILE"
        fi
        return 0
    fi

    log_error "Transit Gateway route for $destination_cidr not found in route table $route_table_id"
    return 1
}

################################################################################
# Test Case Functions
################################################################################

test_case_1_vpc_with_tgw_routing() {
    print_header "Test Case 1: VPC with Transit Gateway Routing"

    local test_file="${SCRIPT_DIR}/01-vpc-with-tgw-routing.yaml"
    local tgw_name="dev-hub-tgw"
    local vpc_name="dev-spoke-vpc-a"
    local attachment_name="dev-hub-tgw-to-spoke-a"
    local destination_cidr="10.1.0.0/16"

    # Apply resources
    log_step "Applying VPC with Transit Gateway routing..."
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would apply $test_file"
        kubectl apply -f "$test_file" --dry-run=client >> "$LOG_FILE" 2>&1
    else
        kubectl apply -f "$test_file" | tee -a "$LOG_FILE"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_success "Test Case 1: DRY RUN completed"
        return 0
    fi

    # Wait for Transit Gateway
    if ! wait_for_resource "transitgateway" "$tgw_name" "$TIMEOUT_TGW"; then
        log_error "Test Case 1 FAILED: Transit Gateway did not become Ready"
        return 1
    fi

    # Get Transit Gateway status
    local tgw_status=$(get_resource_status "transitgateway" "$tgw_name")
    local tgw_id=$(echo "$tgw_status" | jq -r '.status.transitGatewayId // empty')

    if [ -z "$tgw_id" ]; then
        log_error "Test Case 1 FAILED: Transit Gateway ID not found in status"
        return 1
    fi

    log_info "Transit Gateway ID: $tgw_id"

    # Wait for VPC
    if ! wait_for_resource "vpcnetwork" "$vpc_name" "$TIMEOUT_VPC"; then
        log_error "Test Case 1 FAILED: VPC did not become Ready"
        return 1
    fi

    # Get VPC status
    local vpc_status=$(get_resource_status "vpcnetwork" "$vpc_name")
    local vpc_id=$(echo "$vpc_status" | jq -r '.status.vpcId // empty')
    local private_rt_ids=$(echo "$vpc_status" | jq -r '.status.privateRouteTables[]?.id // empty')

    if [ -z "$vpc_id" ]; then
        log_error "Test Case 1 FAILED: VPC ID not found in status"
        return 1
    fi

    log_info "VPC ID: $vpc_id"
    log_info "Private Route Tables: $private_rt_ids"

    # Verify VPC in AWS
    if ! verify_aws_vpc "$vpc_id"; then
        log_error "Test Case 1 FAILED: AWS VPC verification failed"
        return 1
    fi

    # Wait for Attachment
    if ! wait_for_resource "transitgatewayattachment" "$attachment_name" "$TIMEOUT_ATTACHMENT"; then
        log_error "Test Case 1 FAILED: VPC Attachment did not become Ready"
        return 1
    fi

    # Get Attachment status
    local att_status=$(get_resource_status "transitgatewayattachment" "$attachment_name")
    local att_id=$(echo "$att_status" | jq -r '.status.attachmentId // empty')

    if [ -z "$att_id" ]; then
        log_error "Test Case 1 FAILED: Attachment ID not found in status"
        return 1
    fi

    log_info "Attachment ID: $att_id"

    # Verify Transit Gateway routes in private route tables
    log_step "Verifying Transit Gateway routes in private route tables..."
    local route_verification_failed=false
    local route_count=0

    for rt_id in $private_rt_ids; do
        if verify_transit_gateway_routes "$rt_id" "$destination_cidr"; then
            route_count=$((route_count + 1))
        else
            route_verification_failed=true
        fi
    done

    if [ "$route_verification_failed" = true ]; then
        log_error "Test Case 1 FAILED: Not all private route tables have Transit Gateway routes"
        return 1
    fi

    if [ "$route_count" -eq 0 ]; then
        log_error "Test Case 1 FAILED: No Transit Gateway routes found in any private route table"
        return 1
    fi

    log_success "All $route_count private route tables have Transit Gateway routes"

    # Verify connection secrets
    if ! verify_connection_secret "${vpc_name}-connection"; then
        log_error "Test Case 1 FAILED: VPC connection secret verification failed"
        return 1
    fi

    if ! verify_connection_secret "${tgw_name}-connection"; then
        log_error "Test Case 1 FAILED: Transit Gateway connection secret verification failed"
        return 1
    fi

    # Verify label propagation
    log_step "Verifying label propagation from claim to managed resources..."

    # Check VPC labels
    local vpc_managed=$(kubectl get vpc -n "$CROSSPLANE_NAMESPACE" \
        -l "portal-kombat.io/network-claim=$vpc_name" \
        -o jsonpath='{.items[0].metadata.labels}')

    if [ -z "$vpc_managed" ]; then
        log_error "Test Case 1 FAILED: VPC managed resource not found with claim label"
        return 1
    fi

    local vpc_env_label=$(echo "$vpc_managed" | jq -r '.environment // empty')
    if [ "$vpc_env_label" != "dev" ]; then
        log_error "Test Case 1 FAILED: VPC managed resource missing 'environment: dev' label"
        return 1
    fi

    log_success "Label propagation verified: VPC managed resource has correct labels"

    # Check Transit Gateway labels
    local tgw_managed=$(kubectl get transitgateway.ec2.aws.upbound.io -n "$CROSSPLANE_NAMESPACE" \
        -l "portal-kombat.io/network-claim=$tgw_name" \
        -o jsonpath='{.items[0].metadata.labels}')

    if [ -z "$tgw_managed" ]; then
        log_error "Test Case 1 FAILED: Transit Gateway managed resource not found with claim label"
        return 1
    fi

    local tgw_env_label=$(echo "$tgw_managed" | jq -r '.environment // empty')
    if [ "$tgw_env_label" != "dev" ]; then
        log_error "Test Case 1 FAILED: Transit Gateway managed resource missing 'environment: dev' label"
        return 1
    fi

    log_success "Label propagation verified: Transit Gateway managed resource has correct labels"

    log_success "Test Case 1 PASSED: VPC with Transit Gateway Routing"
    return 0
}

test_case_2_end_to_end() {
    print_header "Test Case 2: End-to-End Connectivity Validation"

    log_step "Validating all Phase 2 resources are deployed and healthy..."

    # Check VPCs
    log_step "Checking VPC claims..."
    local vpc_count=$(kubectl get vpcnetwork -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

    if [ "$vpc_count" -eq 0 ]; then
        log_error "Test Case 2 FAILED: No VPC claims found"
        return 1
    fi

    log_success "Found $vpc_count VPC claim(s)"

    # Check Transit Gateways
    log_step "Checking Transit Gateway claims..."
    local tgw_count=$(kubectl get transitgateway -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

    if [ "$tgw_count" -eq 0 ]; then
        log_error "Test Case 2 FAILED: No Transit Gateway claims found"
        return 1
    fi

    log_success "Found $tgw_count Transit Gateway claim(s)"

    # Check Attachments
    log_step "Checking Transit Gateway Attachment claims..."
    local att_count=$(kubectl get transitgatewayattachment -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

    if [ "$att_count" -eq 0 ]; then
        log_error "Test Case 2 FAILED: No Transit Gateway Attachment claims found"
        return 1
    fi

    log_success "Found $att_count Transit Gateway Attachment claim(s)"

    # Verify all resources are Ready
    log_step "Verifying all resources are Ready..."

    local vpc_ready=$(kubectl get vpcnetwork -n "$NAMESPACE" -o json | \
        jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

    if [ "$vpc_ready" -ne "$vpc_count" ]; then
        log_error "Test Case 2 FAILED: Only $vpc_ready/$vpc_count VPCs are Ready"
        return 1
    fi

    log_success "All VPCs Ready ($vpc_ready/$vpc_count)"

    local tgw_ready=$(kubectl get transitgateway -n "$NAMESPACE" -o json | \
        jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

    if [ "$tgw_ready" -ne "$tgw_count" ]; then
        log_error "Test Case 2 FAILED: Only $tgw_ready/$tgw_count Transit Gateways are Ready"
        return 1
    fi

    log_success "All Transit Gateways Ready ($tgw_ready/$tgw_count)"

    local att_ready=$(kubectl get transitgatewayattachment -n "$NAMESPACE" -o json | \
        jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')

    if [ "$att_ready" -ne "$att_count" ]; then
        log_error "Test Case 2 FAILED: Only $att_ready/$att_count Attachments are Ready"
        return 1
    fi

    log_success "All Attachments Ready ($att_ready/$att_count)"

    # Verify Transit Gateway routes exist
    log_step "Verifying Transit Gateway routes in all VPCs..."

    local vpcs=$(kubectl get vpcnetwork -n "$NAMESPACE" -o json | jq -r '.items[].metadata.name')
    for vpc_name in $vpcs; do
        local vpc_status=$(get_resource_status "vpcnetwork" "$vpc_name")
        local has_tgw_routing=$(echo "$vpc_status" | jq -r '.spec.parameters.transitGatewayRouting.enabled // false')

        if [ "$has_tgw_routing" = "true" ]; then
            local vpc_id=$(echo "$vpc_status" | jq -r '.status.vpcId // empty')
            local private_rt_ids=$(echo "$vpc_status" | jq -r '.status.privateRouteTables[]?.id // empty')
            local dest_cidrs=$(echo "$vpc_status" | jq -r '.spec.parameters.transitGatewayRouting.destinationCidrBlocks[]? // empty')

            log_info "Checking VPC $vpc_name ($vpc_id) for Transit Gateway routes..."

            for dest_cidr in $dest_cidrs; do
                for rt_id in $private_rt_ids; do
                    if ! verify_transit_gateway_routes "$rt_id" "$dest_cidr"; then
                        log_warning "Transit Gateway route for $dest_cidr not found in $rt_id"
                    fi
                done
            done
        fi
    done

    log_success "Test Case 2 PASSED: End-to-End Connectivity Validation"
    return 0
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --test-case)
                TEST_CASE="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Print header
    print_header "Phase 2 Integration Test Suite"
    log_info "Test run started: $(date)"
    log_info "Log file: $LOG_FILE"

    # Check prerequisites
    check_prerequisites

    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN mode enabled - no resources will be applied"
    fi

    # Run tests
    local failed_tests=0
    local passed_tests=0

    if [ -n "$TEST_CASE" ]; then
        log_info "Running Test Case $TEST_CASE only"
        case "$TEST_CASE" in
            1)
                test_case_1_vpc_with_tgw_routing || failed_tests=$((failed_tests + 1))
                ;;
            2)
                test_case_2_end_to_end || failed_tests=$((failed_tests + 1))
                ;;
            *)
                log_error "Invalid test case: $TEST_CASE"
                exit 1
                ;;
        esac
    else
        log_info "Running all test cases"

        test_case_1_vpc_with_tgw_routing && passed_tests=$((passed_tests + 1)) || failed_tests=$((failed_tests + 1))
        test_case_2_end_to_end && passed_tests=$((passed_tests + 1)) || failed_tests=$((failed_tests + 1))
    fi

    # Print summary
    print_header "Test Summary"
    log_info "Total tests run: $((passed_tests + failed_tests))"
    log_info "Tests passed: $passed_tests"
    log_info "Tests failed: $failed_tests"
    log_info "Test run completed: $(date)"
    log_info "Full log: $LOG_FILE"

    if [ "$failed_tests" -eq 0 ]; then
        log_success "All tests PASSED ✅"
        exit 0
    else
        log_error "Some tests FAILED ❌"
        log_error "Review log file for details: $LOG_FILE"
        exit 1
    fi
}

# Run main function
main "$@"
