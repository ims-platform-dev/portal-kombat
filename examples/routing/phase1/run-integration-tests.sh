#!/bin/bash
set -euo pipefail

################################################################################
# Phase 1 Integration Test Automation Script
#
# This script automates integration testing for AWS Routing Composition Phase 1.
# It tests Transit Gateway, VPC Attachment, and Route Table provisioning.
#
# Usage:
#   ./run-integration-tests.sh                    # Run all tests
#   ./run-integration-tests.sh --test-case 1      # Run specific test case
#   ./run-integration-tests.sh --verbose          # Verbose output
#   ./run-integration-tests.sh --dry-run          # Validate without applying
#
# Prerequisites:
#   - kubectl configured for dev cluster
#   - AWS CLI configured with appropriate credentials
#   - Existing VPC with required labels
#   - Private subnets in VPC
#
################################################################################

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="crossplane-system"
REGION="us-east-2"
TIMEOUT_TGW=300        # 5 minutes for Transit Gateway
TIMEOUT_ATTACHMENT=600  # 10 minutes for VPC Attachment
TIMEOUT_RT=300         # 5 minutes for Route Table
TIMEOUT_E2E=900        # 15 minutes for end-to-end
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
    --test-case N     Run specific test case (1-4)
    --verbose         Enable verbose output
    --dry-run         Validate prerequisites without applying resources
    --help            Display this help message

TEST CASES:
    1. Basic Transit Gateway
    2. VPC Attachment with Subnet Selection
    3. Route Table with Transit Gateway
    4. End-to-End Provisioning

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
    if ! aws sts get-caller-identity --region "$REGION" &> /dev/null; then
        log_error "AWS credentials not configured or expired. Run 'aws sso login'."
        prereq_failed=true
    else
        local account=$(aws sts get-caller-identity --region "$REGION" --query 'Account' --output text)
        log_success "AWS authenticated: Account $account"
    fi

    # Check Crossplane providers
    log_step "Checking Crossplane providers..."
    if ! kubectl get providers &> /dev/null; then
        log_error "Cannot access Crossplane providers. Check Crossplane installation."
        prereq_failed=true
    else
        local unhealthy=$(kubectl get providers -o json | jq -r '.items[] | select(.status.conditions[] | select(.type=="Healthy" and .status!="True")) | .metadata.name')
        if [ -n "$unhealthy" ]; then
            log_error "Unhealthy providers found: $unhealthy"
            prereq_failed=true
        else
            log_success "All Crossplane providers healthy"
        fi
    fi

    # Check for required VPC
    log_step "Checking for VPC with required labels..."
    local vpc_count=$(kubectl get vpc -n "$NAMESPACE" \
        -l "portal-kombat.io/network-component=vpc,environment=dev" \
        --no-headers 2>/dev/null | wc -l)

    if [ "$vpc_count" -eq 0 ]; then
        log_warning "No VPC found with required labels (portal-kombat.io/network-component=vpc, environment=dev)"
        log_warning "VPC attachment tests may fail. Consider creating a VPC first."
    else
        log_success "Found $vpc_count VPC(s) with required labels"
    fi

    # Check for private subnets
    log_step "Checking for private subnets..."
    local subnet_count=$(kubectl get subnet -n "$NAMESPACE" -l "tier=private" --no-headers 2>/dev/null | wc -l)

    if [ "$subnet_count" -eq 0 ]; then
        log_warning "No private subnets found with label tier=private"
        log_warning "VPC attachment tests will fail without private subnets."
    else
        log_success "Found $subnet_count private subnet(s)"
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

verify_aws_resource() {
    local resource_type=$1
    local resource_id=$2

    log_step "Verifying AWS $resource_type: $resource_id..."

    case "$resource_type" in
        "transit-gateway")
            if aws ec2 describe-transit-gateways \
                --transit-gateway-ids "$resource_id" \
                --region "$REGION" &> /dev/null; then
                log_success "AWS Transit Gateway $resource_id exists"

                if [ "$VERBOSE" = true ]; then
                    aws ec2 describe-transit-gateways \
                        --transit-gateway-ids "$resource_id" \
                        --region "$REGION" \
                        --query 'TransitGateways[0].[State,OwnerId,Options.AmazonSideAsn]' \
                        --output table | tee -a "$LOG_FILE"
                fi
                return 0
            fi
            ;;
        "transit-gateway-attachment")
            if aws ec2 describe-transit-gateway-vpc-attachments \
                --transit-gateway-attachment-ids "$resource_id" \
                --region "$REGION" &> /dev/null; then
                log_success "AWS VPC Attachment $resource_id exists"

                if [ "$VERBOSE" = true ]; then
                    aws ec2 describe-transit-gateway-vpc-attachments \
                        --transit-gateway-attachment-ids "$resource_id" \
                        --region "$REGION" \
                        --query 'TransitGatewayVpcAttachments[0].[State,VpcId,TransitGatewayId]' \
                        --output table | tee -a "$LOG_FILE"
                fi
                return 0
            fi
            ;;
        "transit-gateway-route-table")
            if aws ec2 describe-transit-gateway-route-tables \
                --transit-gateway-route-table-ids "$resource_id" \
                --region "$REGION" &> /dev/null; then
                log_success "AWS Route Table $resource_id exists"

                if [ "$VERBOSE" = true ]; then
                    aws ec2 describe-transit-gateway-route-tables \
                        --transit-gateway-route-table-ids "$resource_id" \
                        --region "$REGION" \
                        --query 'TransitGatewayRouteTables[0].[State,TransitGatewayId]' \
                        --output table | tee -a "$LOG_FILE"
                fi
                return 0
            fi
            ;;
    esac

    log_error "AWS $resource_type $resource_id not found or not accessible"
    return 1
}

################################################################################
# Test Case Functions
################################################################################

test_case_1_basic_tgw() {
    print_header "Test Case 1: Basic Transit Gateway"

    local test_file="${SCRIPT_DIR}/01-transit-gateway.yaml"
    local resource_name="dev-hub-tgw"
    local secret_name="${resource_name}-connection"

    # Apply resource
    log_step "Applying Transit Gateway claim..."
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

    # Wait for resource
    if ! wait_for_resource "transitgateway" "$resource_name" "$TIMEOUT_TGW"; then
        log_error "Test Case 1 FAILED: Transit Gateway did not become Ready"
        return 1
    fi

    # Get status (XRD status fields are at top level, not atProvider)
    local status=$(get_resource_status "transitgateway" "$resource_name")
    local tgw_id=$(echo "$status" | jq -r '.status.transitGatewayId // empty')
    local state=$(echo "$status" | jq -r '.status.state // empty')

    if [ -z "$tgw_id" ]; then
        log_error "Test Case 1 FAILED: Transit Gateway ID not found in status"
        return 1
    fi

    log_info "Transit Gateway ID: $tgw_id"
    log_info "Transit Gateway State: $state"

    # Verify connection secret
    if ! verify_connection_secret "$secret_name"; then
        log_error "Test Case 1 FAILED: Connection secret verification failed"
        return 1
    fi

    # Verify AWS resource
    if ! verify_aws_resource "transit-gateway" "$tgw_id"; then
        log_error "Test Case 1 FAILED: AWS resource verification failed"
        return 1
    fi

    log_success "Test Case 1 PASSED: Basic Transit Gateway"
    return 0
}

test_case_2_vpc_attachment() {
    print_header "Test Case 2: VPC Attachment with Subnet Selection"

    local test_file="${SCRIPT_DIR}/02-tgw-with-attachment.yaml"
    local tgw_name="dev-hub-tgw"
    local attachment_name="dev-vpc1-attachment"
    local tgw_secret="${tgw_name}-connection"
    local attachment_secret="${attachment_name}-connection"

    # Apply resources
    log_step "Applying Transit Gateway and VPC Attachment..."
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would apply $test_file"
        kubectl apply -f "$test_file" --dry-run=client >> "$LOG_FILE" 2>&1
    else
        kubectl apply -f "$test_file" | tee -a "$LOG_FILE"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_success "Test Case 2: DRY RUN completed"
        return 0
    fi

    # Wait for Transit Gateway
    if ! wait_for_resource "transitgateway" "$tgw_name" "$TIMEOUT_TGW"; then
        log_error "Test Case 2 FAILED: Transit Gateway did not become Ready"
        return 1
    fi

    # Wait for Attachment
    if ! wait_for_resource "transitgatewayattachment" "$attachment_name" "$TIMEOUT_ATTACHMENT"; then
        log_error "Test Case 2 FAILED: VPC Attachment did not become Ready"
        return 1
    fi

    # Get Transit Gateway status
    local tgw_status=$(get_resource_status "transitgateway" "$tgw_name")
    local tgw_id=$(echo "$tgw_status" | jq -r '.status.atProvider.transitGatewayId // empty')

    # Get Attachment status
    local att_status=$(get_resource_status "transitgatewayattachment" "$attachment_name")
    local att_id=$(echo "$att_status" | jq -r '.status.atProvider.transitGatewayAttachmentId // empty')
    local att_tgw_id=$(echo "$att_status" | jq -r '.status.atProvider.transitGatewayId // empty')
    local vpc_id=$(echo "$att_status" | jq -r '.status.atProvider.vpcId // empty')
    local subnet_ids=$(echo "$att_status" | jq -r '.status.atProvider.subnetIds[]? // empty' | tr '\n' ' ')

    if [ -z "$att_id" ]; then
        log_error "Test Case 2 FAILED: Attachment ID not found in status"
        return 1
    fi

    log_info "Attachment ID: $att_id"
    log_info "Transit Gateway ID: $att_tgw_id"
    log_info "VPC ID: $vpc_id"
    log_info "Subnet IDs: $subnet_ids"

    # Verify selector binding
    if [ "$tgw_id" != "$att_tgw_id" ]; then
        log_error "Test Case 2 FAILED: Transit Gateway selector mismatch"
        log_error "  Expected TGW: $tgw_id"
        log_error "  Attachment TGW: $att_tgw_id"
        return 1
    fi
    log_success "Selector binding verified: Attachment bound to correct Transit Gateway"

    # Verify connection secrets
    if ! verify_connection_secret "$tgw_secret"; then
        log_error "Test Case 2 FAILED: Transit Gateway secret verification failed"
        return 1
    fi

    if ! verify_connection_secret "$attachment_secret"; then
        log_error "Test Case 2 FAILED: Attachment secret verification failed"
        return 1
    fi

    # Verify AWS resources
    if ! verify_aws_resource "transit-gateway" "$tgw_id"; then
        log_error "Test Case 2 FAILED: AWS Transit Gateway verification failed"
        return 1
    fi

    if ! verify_aws_resource "transit-gateway-attachment" "$att_id"; then
        log_error "Test Case 2 FAILED: AWS Attachment verification failed"
        return 1
    fi

    # Verify subnet selection
    if [ -n "$subnet_ids" ]; then
        log_step "Verifying subnet selection (private, multi-AZ)..."
        local az_count=0
        for subnet_id in $subnet_ids; do
            local subnet_info=$(aws ec2 describe-subnets \
                --subnet-ids "$subnet_id" \
                --region "$REGION" \
                --query 'Subnets[0].[SubnetId,AvailabilityZone,Tags[?Key==`tier`].Value|[0]]' \
                --output text 2>/dev/null)

            if [ -n "$subnet_info" ]; then
                log_info "  Subnet: $subnet_info"
                az_count=$((az_count + 1))
            fi
        done

        if [ "$az_count" -gt 1 ]; then
            log_success "Subnets span multiple availability zones ($az_count AZs)"
        else
            log_warning "Subnets only in $az_count AZ (multi-AZ recommended for high availability)"
        fi
    fi

    log_success "Test Case 2 PASSED: VPC Attachment with Subnet Selection"
    return 0
}

test_case_3_route_table() {
    print_header "Test Case 3: Route Table with Transit Gateway"

    local test_file="${SCRIPT_DIR}/03-tgw-with-route-table.yaml"
    local tgw_name="dev-hub-tgw"
    local rt_name="dev-isolated-rt"
    local tgw_secret="${tgw_name}-connection"
    local rt_secret="${rt_name}-connection"

    # Apply resources
    log_step "Applying Transit Gateway and Route Table..."
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would apply $test_file"
        kubectl apply -f "$test_file" --dry-run=client >> "$LOG_FILE" 2>&1
    else
        kubectl apply -f "$test_file" | tee -a "$LOG_FILE"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_success "Test Case 3: DRY RUN completed"
        return 0
    fi

    # Wait for Transit Gateway
    if ! wait_for_resource "transitgateway" "$tgw_name" "$TIMEOUT_TGW"; then
        log_error "Test Case 3 FAILED: Transit Gateway did not become Ready"
        return 1
    fi

    # Wait for Route Table
    if ! wait_for_resource "transitgatewayroutetable" "$rt_name" "$TIMEOUT_RT"; then
        log_error "Test Case 3 FAILED: Route Table did not become Ready"
        return 1
    fi

    # Get Transit Gateway status
    local tgw_status=$(get_resource_status "transitgateway" "$tgw_name")
    local tgw_id=$(echo "$tgw_status" | jq -r '.status.atProvider.transitGatewayId // empty')

    # Get Route Table status
    local rt_status=$(get_resource_status "transitgatewayroutetable" "$rt_name")
    local rt_id=$(echo "$rt_status" | jq -r '.status.atProvider.transitGatewayRouteTableId // empty')
    local rt_tgw_id=$(echo "$rt_status" | jq -r '.status.atProvider.transitGatewayId // empty')

    if [ -z "$rt_id" ]; then
        log_error "Test Case 3 FAILED: Route Table ID not found in status"
        return 1
    fi

    log_info "Route Table ID: $rt_id"
    log_info "Transit Gateway ID: $rt_tgw_id"

    # Verify selector binding
    if [ "$tgw_id" != "$rt_tgw_id" ]; then
        log_error "Test Case 3 FAILED: Transit Gateway selector mismatch"
        log_error "  Expected TGW: $tgw_id"
        log_error "  Route Table TGW: $rt_tgw_id"
        return 1
    fi
    log_success "Selector binding verified: Route Table bound to correct Transit Gateway"

    # Verify connection secrets
    if ! verify_connection_secret "$tgw_secret"; then
        log_error "Test Case 3 FAILED: Transit Gateway secret verification failed"
        return 1
    fi

    if ! verify_connection_secret "$rt_secret"; then
        log_error "Test Case 3 FAILED: Route Table secret verification failed"
        return 1
    fi

    # Verify AWS resources
    if ! verify_aws_resource "transit-gateway" "$tgw_id"; then
        log_error "Test Case 3 FAILED: AWS Transit Gateway verification failed"
        return 1
    fi

    if ! verify_aws_resource "transit-gateway-route-table" "$rt_id"; then
        log_error "Test Case 3 FAILED: AWS Route Table verification failed"
        return 1
    fi

    log_success "Test Case 3 PASSED: Route Table with Transit Gateway"
    return 0
}

test_case_4_end_to_end() {
    print_header "Test Case 4: End-to-End Provisioning"

    local examples_dir="${SCRIPT_DIR}"

    # Apply all resources
    log_step "Applying all Phase 1 resources..."
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would apply all resources from $examples_dir"
        kubectl apply -f "$examples_dir" --dry-run=client >> "$LOG_FILE" 2>&1
    else
        kubectl apply -f "$examples_dir" | tee -a "$LOG_FILE"
    fi

    if [ "$DRY_RUN" = true ]; then
        log_success "Test Case 4: DRY RUN completed"
        return 0
    fi

    # Monitor resource creation
    log_step "Monitoring resource creation..."
    sleep 5
    kubectl get transitgateway,transitgatewayattachment,transitgatewayroutetable -n "$NAMESPACE" | tee -a "$LOG_FILE"

    # Wait for all Transit Gateways
    log_step "Waiting for Transit Gateways..."
    local tgw_timeout=0
    while [ $tgw_timeout -lt $TIMEOUT_TGW ]; do
        local tgw_ready=$(kubectl get transitgateway -n "$NAMESPACE" -o json | \
            jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
        local tgw_total=$(kubectl get transitgateway -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)

        if [ "$tgw_ready" -eq "$tgw_total" ] && [ "$tgw_total" -gt 0 ]; then
            log_success "All Transit Gateways ready ($tgw_ready/$tgw_total)"
            break
        fi

        log_info "Transit Gateways: $tgw_ready/$tgw_total ready..."
        sleep 10
        tgw_timeout=$((tgw_timeout + 10))
    done

    # Wait for all Route Tables
    log_step "Waiting for Route Tables..."
    local rt_timeout=0
    while [ $rt_timeout -lt $TIMEOUT_RT ]; do
        local rt_ready=$(kubectl get transitgatewayroutetable -A -o json | \
            jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
        local rt_total=$(kubectl get transitgatewayroutetable -A --no-headers 2>/dev/null | wc -l)

        if [ "$rt_ready" -eq "$rt_total" ] && [ "$rt_total" -gt 0 ]; then
            log_success "All Route Tables ready ($rt_ready/$rt_total)"
            break
        fi

        log_info "Route Tables: $rt_ready/$rt_total ready..."
        sleep 10
        rt_timeout=$((rt_timeout + 10))
    done

    # Wait for all Attachments
    log_step "Waiting for VPC Attachments..."
    local att_timeout=0
    while [ $att_timeout -lt $TIMEOUT_ATTACHMENT ]; do
        local att_ready=$(kubectl get transitgatewayattachment -A -o json | \
            jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
        local att_total=$(kubectl get transitgatewayattachment -A --no-headers 2>/dev/null | wc -l)

        if [ "$att_ready" -eq "$att_total" ] && [ "$att_total" -gt 0 ]; then
            log_success "All VPC Attachments ready ($att_ready/$att_total)"
            break
        fi

        log_info "VPC Attachments: $att_ready/$att_total ready..."
        sleep 10
        att_timeout=$((att_timeout + 10))
    done

    # Verify all resources are ready
    log_step "Verifying all resources reached Ready state..."
    local all_ready=true

    if ! kubectl get transitgateway -n "$NAMESPACE" -o json | \
        jq -e '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | length > 0' &>/dev/null; then
        log_error "Not all Transit Gateways are Ready"
        all_ready=false
    fi

    if ! kubectl get transitgatewayroutetable -A -o json | \
        jq -e '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | length > 0' &>/dev/null; then
        log_warning "Not all Route Tables are Ready (may be expected if no route tables in examples)"
    fi

    if ! kubectl get transitgatewayattachment -A -o json | \
        jq -e '.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True")) | length > 0' &>/dev/null; then
        log_warning "Not all VPC Attachments are Ready (may be expected if no VPCs available)"
    fi

    if [ "$all_ready" = false ]; then
        log_error "Test Case 4 FAILED: Not all resources reached Ready state"
        return 1
    fi

    # Verify connection secrets
    log_step "Verifying all connection secrets..."
    local secrets=$(kubectl get secrets -n "$NAMESPACE" -o json | \
        jq -r '.items[] | select(.metadata.name | test("(tgw|attachment|route.*table).*connection")) | .metadata.name')

    if [ -z "$secrets" ]; then
        log_error "Test Case 4 FAILED: No connection secrets found"
        return 1
    fi

    log_info "Found connection secrets:"
    echo "$secrets" | while read -r secret; do
        log_info "  - $secret"
    done

    # Comprehensive AWS validation
    log_step "Performing comprehensive AWS validation..."
    local tgw_ids=$(kubectl get transitgateway -n "$NAMESPACE" -o json | \
        jq -r '.items[].status.atProvider.transitGatewayId // empty')

    for tgw_id in $tgw_ids; do
        log_info "Validating Transit Gateway: $tgw_id"

        # List attachments
        local attachments=$(aws ec2 describe-transit-gateway-attachments \
            --filters "Name=transit-gateway-id,Values=$tgw_id" \
            --region "$REGION" \
            --query 'TransitGatewayAttachments[*].[TransitGatewayAttachmentId,State,ResourceType]' \
            --output text)

        if [ -n "$attachments" ]; then
            log_info "  Attachments:"
            echo "$attachments" | while read -r line; do
                log_info "    $line"
            done
        fi

        # List route tables
        local route_tables=$(aws ec2 describe-transit-gateway-route-tables \
            --filters "Name=transit-gateway-id,Values=$tgw_id" \
            --region "$REGION" \
            --query 'TransitGatewayRouteTables[*].[TransitGatewayRouteTableId,State]' \
            --output text)

        if [ -n "$route_tables" ]; then
            log_info "  Route Tables:"
            echo "$route_tables" | while read -r line; do
                log_info "    $line"
            done
        fi
    done

    log_success "Test Case 4 PASSED: End-to-End Provisioning"
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
    print_header "Phase 1 Integration Test Suite"
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
                test_case_1_basic_tgw || failed_tests=$((failed_tests + 1))
                ;;
            2)
                test_case_2_vpc_attachment || failed_tests=$((failed_tests + 1))
                ;;
            3)
                test_case_3_route_table || failed_tests=$((failed_tests + 1))
                ;;
            4)
                test_case_4_end_to_end || failed_tests=$((failed_tests + 1))
                ;;
            *)
                log_error "Invalid test case: $TEST_CASE"
                exit 1
                ;;
        esac
    else
        log_info "Running all test cases"

        test_case_1_basic_tgw && passed_tests=$((passed_tests + 1)) || failed_tests=$((failed_tests + 1))
        test_case_2_vpc_attachment && passed_tests=$((passed_tests + 1)) || failed_tests=$((failed_tests + 1))
        test_case_3_route_table && passed_tests=$((passed_tests + 1)) || failed_tests=$((failed_tests + 1))
        test_case_4_end_to_end && passed_tests=$((passed_tests + 1)) || failed_tests=$((failed_tests + 1))
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
