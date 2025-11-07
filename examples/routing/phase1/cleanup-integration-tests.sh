#!/bin/bash
set -euo pipefail

################################################################################
# Phase 1 Integration Test Cleanup Script
#
# This script safely removes all resources created during Phase 1 integration
# testing. It deletes resources in the correct dependency order to avoid
# orphaned AWS resources.
#
# Usage:
#   ./cleanup-integration-tests.sh                    # Interactive cleanup
#   ./cleanup-integration-tests.sh --force            # Skip confirmation
#   ./cleanup-integration-tests.sh --verify-only      # Check for resources only
#   ./cleanup-integration-tests.sh --aws-cleanup      # Clean orphaned AWS resources
#
# Safety Features:
#   - Deletes in reverse dependency order (attachments → route tables → TGW)
#   - Verifies resources are deleted from AWS
#   - Detects and reports orphaned AWS resources
#   - Requires confirmation by default (use --force to skip)
#
################################################################################

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="crossplane-system"
REGION="us-east-2"
DELETE_TIMEOUT=600  # 10 minutes max wait per resource
FORCE=false
VERIFY_ONLY=false
AWS_CLEANUP=false
LOG_FILE="${SCRIPT_DIR}/cleanup-$(date +%Y%m%d-%H%M%S).log"

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
    echo -e "${BLUE}ℹ ${NC}$*"
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
    --force           Skip confirmation prompts
    --verify-only     Check for resources without deleting
    --aws-cleanup     Clean up orphaned AWS resources
    --help            Display this help message

EXAMPLES:
    $(basename "$0")                    # Interactive cleanup with confirmation
    $(basename "$0") --force            # Automatic cleanup without confirmation
    $(basename "$0") --verify-only      # Check what resources exist
    $(basename "$0") --aws-cleanup      # Clean orphaned AWS resources

CLEANUP ORDER:
    1. VPC Attachments (dependent on Transit Gateway)
    2. Route Tables (dependent on Transit Gateway)
    3. Transit Gateways (can be deleted last)
    4. Connection Secrets (cleanup metadata)

EOF
    exit 0
}

confirm_deletion() {
    if [ "$FORCE" = true ]; then
        return 0
    fi

    local resource_count=$1
    local resource_type=$2

    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will delete $resource_count $resource_type${NC}"
    echo -e "${YELLOW}⚠️  This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi

    return 0
}

list_resources() {
    print_header "Discovering Phase 1 Resources"

    local found_resources=false

    # Transit Gateways
    log_step "Checking for Transit Gateways..."
    local tgw_count=$(kubectl get transitgateway -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
    if [ "$tgw_count" -gt 0 ]; then
        log_info "Found $tgw_count Transit Gateway(s):"
        kubectl get transitgateway -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,ID:.status.atProvider.transitGatewayId,STATE:.status.atProvider.state 2>/dev/null | tee -a "$LOG_FILE"
        found_resources=true
    else
        log_info "No Transit Gateways found"
    fi

    # VPC Attachments
    log_step "Checking for VPC Attachments..."
    local att_count=$(kubectl get transitgatewayattachment -A --no-headers 2>/dev/null | wc -l)
    if [ "$att_count" -gt 0 ]; then
        log_info "Found $att_count VPC Attachment(s):"
        kubectl get transitgatewayattachment -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,ID:.status.atProvider.transitGatewayAttachmentId,STATE:.status.atProvider.state 2>/dev/null | tee -a "$LOG_FILE"
        found_resources=true
    else
        log_info "No VPC Attachments found"
    fi

    # Route Tables
    log_step "Checking for Route Tables..."
    local rt_count=$(kubectl get transitgatewayroutetable -A --no-headers 2>/dev/null | wc -l)
    if [ "$rt_count" -gt 0 ]; then
        log_info "Found $rt_count Route Table(s):"
        kubectl get transitgatewayroutetable -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,ID:.status.atProvider.transitGatewayRouteTableId,STATE:.status.atProvider.state 2>/dev/null | tee -a "$LOG_FILE"
        found_resources=true
    else
        log_info "No Route Tables found"
    fi

    # Connection Secrets
    log_step "Checking for Connection Secrets..."
    local secrets=$(kubectl get secrets -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | test("(tgw|attachment|route.*table).*connection")) | .metadata.name')

    if [ -n "$secrets" ]; then
        log_info "Found connection secrets:"
        echo "$secrets" | while read -r secret; do
            log_info "  - $secret"
        done
        found_resources=true
    else
        log_info "No connection secrets found"
    fi

    if [ "$found_resources" = false ]; then
        log_success "No Phase 1 resources found - environment is clean"
        return 1
    fi

    return 0
}

delete_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$NAMESPACE}

    log_step "Deleting $resource_type/$resource_name in namespace $namespace..."

    if kubectl delete "$resource_type/$resource_name" -n "$namespace" --timeout="${DELETE_TIMEOUT}s" &>> "$LOG_FILE"; then
        log_success "$resource_type/$resource_name deleted"
        return 0
    else
        log_error "Failed to delete $resource_type/$resource_name"
        return 1
    fi
}

wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-$NAMESPACE}
    local timeout=${4:-$DELETE_TIMEOUT}

    log_step "Waiting for $resource_type/$resource_name to be fully deleted (timeout: ${timeout}s)..."

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ! kubectl get "$resource_type/$resource_name" -n "$namespace" &> /dev/null; then
            log_success "$resource_type/$resource_name fully deleted"
            return 0
        fi

        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "Still waiting for deletion... ($elapsed/${timeout}s)"
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "$resource_type/$resource_name deletion timed out"
    return 1
}

verify_aws_deletion() {
    local resource_type=$1
    local resource_id=$2

    log_step "Verifying AWS $resource_type $resource_id is deleted..."

    case "$resource_type" in
        "transit-gateway")
            if aws ec2 describe-transit-gateways \
                --transit-gateway-ids "$resource_id" \
                --region "$REGION" &> /dev/null; then
                log_error "AWS Transit Gateway $resource_id still exists"
                return 1
            fi
            ;;
        "transit-gateway-attachment")
            if aws ec2 describe-transit-gateway-vpc-attachments \
                --transit-gateway-attachment-ids "$resource_id" \
                --region "$REGION" &> /dev/null; then
                log_error "AWS VPC Attachment $resource_id still exists"
                return 1
            fi
            ;;
        "transit-gateway-route-table")
            if aws ec2 describe-transit-gateway-route-tables \
                --transit-gateway-route-table-ids "$resource_id" \
                --region "$REGION" &> /dev/null; then
                log_error "AWS Route Table $resource_id still exists"
                return 1
            fi
            ;;
    esac

    log_success "AWS $resource_type $resource_id verified deleted"
    return 0
}

delete_attachments() {
    print_header "Deleting VPC Attachments"

    local attachments=$(kubectl get transitgatewayattachment -A -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.status.atProvider.transitGatewayAttachmentId // "")"')

    if [ -z "$attachments" ]; then
        log_info "No VPC Attachments to delete"
        return 0
    fi

    local att_count=$(echo "$attachments" | wc -l)
    confirm_deletion "$att_count" "VPC Attachment(s)"

    echo "$attachments" | while read -r ns name att_id; do
        delete_resource "transitgatewayattachment" "$name" "$ns"

        # Wait for deletion to complete
        wait_for_deletion "transitgatewayattachment" "$name" "$ns"

        # Verify in AWS
        if [ -n "$att_id" ] && [ "$att_id" != "null" ]; then
            verify_aws_deletion "transit-gateway-attachment" "$att_id"
        fi
    done

    log_success "All VPC Attachments deleted"
}

delete_route_tables() {
    print_header "Deleting Route Tables"

    local route_tables=$(kubectl get transitgatewayroutetable -A -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.status.atProvider.transitGatewayRouteTableId // "")"')

    if [ -z "$route_tables" ]; then
        log_info "No Route Tables to delete"
        return 0
    fi

    local rt_count=$(echo "$route_tables" | wc -l)
    confirm_deletion "$rt_count" "Route Table(s)"

    echo "$route_tables" | while read -r ns name rt_id; do
        delete_resource "transitgatewayroutetable" "$name" "$ns"

        # Wait for deletion to complete
        wait_for_deletion "transitgatewayroutetable" "$name" "$ns"

        # Verify in AWS
        if [ -n "$rt_id" ] && [ "$rt_id" != "null" ]; then
            verify_aws_deletion "transit-gateway-route-table" "$rt_id"
        fi
    done

    log_success "All Route Tables deleted"
}

delete_transit_gateways() {
    print_header "Deleting Transit Gateways"

    local tgws=$(kubectl get transitgateway -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.name) \(.status.atProvider.transitGatewayId // "")"')

    if [ -z "$tgws" ]; then
        log_info "No Transit Gateways to delete"
        return 0
    fi

    local tgw_count=$(echo "$tgws" | wc -l)
    confirm_deletion "$tgw_count" "Transit Gateway(s)"

    echo "$tgws" | while read -r name tgw_id; do
        delete_resource "transitgateway" "$name" "$NAMESPACE"

        # Wait for deletion to complete
        wait_for_deletion "transitgateway" "$name" "$NAMESPACE"

        # Verify in AWS
        if [ -n "$tgw_id" ] && [ "$tgw_id" != "null" ]; then
            verify_aws_deletion "transit-gateway" "$tgw_id"
        fi
    done

    log_success "All Transit Gateways deleted"
}

delete_connection_secrets() {
    print_header "Cleaning Up Connection Secrets"

    local secrets=$(kubectl get secrets -n "$NAMESPACE" -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | test("(tgw|attachment|route.*table).*connection")) | .metadata.name')

    if [ -z "$secrets" ]; then
        log_info "No connection secrets to delete"
        return 0
    fi

    local secret_count=$(echo "$secrets" | wc -l)
    log_info "Found $secret_count connection secret(s)"

    echo "$secrets" | while read -r secret; do
        if kubectl delete secret "$secret" -n "$NAMESPACE" &>> "$LOG_FILE"; then
            log_success "Deleted secret: $secret"
        else
            log_warning "Failed to delete secret: $secret (may have been auto-deleted)"
        fi
    done

    log_success "Connection secrets cleanup complete"
}

cleanup_orphaned_aws_resources() {
    print_header "Checking for Orphaned AWS Resources"

    log_warning "This will search for and optionally delete AWS resources tagged with project=portal-kombat"
    log_warning "that may not be managed by Crossplane anymore."

    if [ "$FORCE" = false ]; then
        echo ""
        read -p "Continue with orphaned resource check? (yes/no): " -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Orphaned resource check cancelled"
            return 0
        fi
    fi

    # Check for orphaned Transit Gateways
    log_step "Checking for orphaned Transit Gateways..."
    local orphaned_tgws=$(aws ec2 describe-transit-gateways \
        --filters "Name=tag:project,Values=portal-kombat" "Name=state,Values=available,pending" \
        --region "$REGION" \
        --query 'TransitGateways[*].[TransitGatewayId,State,Tags[?Key==`managedBy`].Value|[0]]' \
        --output text 2>/dev/null)

    if [ -n "$orphaned_tgws" ]; then
        log_warning "Found potentially orphaned Transit Gateways:"
        echo "$orphaned_tgws" | while read -r tgw_id state managed_by; do
            log_info "  $tgw_id (State: $state, ManagedBy: ${managed_by:-unknown})"

            # Check if still in Crossplane
            local in_crossplane=$(kubectl get transitgateway -n "$NAMESPACE" -o json 2>/dev/null | \
                jq -r ".items[] | select(.status.atProvider.transitGatewayId==\"$tgw_id\") | .metadata.name")

            if [ -z "$in_crossplane" ]; then
                log_warning "  → NOT FOUND in Crossplane - likely orphaned"

                if [ "$FORCE" = true ]; then
                    log_info "  → Deleting orphaned Transit Gateway $tgw_id..."
                    if aws ec2 delete-transit-gateway --transit-gateway-id "$tgw_id" --region "$REGION" &>> "$LOG_FILE"; then
                        log_success "  → Deleted $tgw_id"
                    else
                        log_error "  → Failed to delete $tgw_id"
                    fi
                fi
            else
                log_info "  → Found in Crossplane as: $in_crossplane"
            fi
        done
    else
        log_success "No orphaned Transit Gateways found"
    fi

    # Check for orphaned VPC Attachments
    log_step "Checking for orphaned VPC Attachments..."
    local orphaned_atts=$(aws ec2 describe-transit-gateway-attachments \
        --filters "Name=tag:project,Values=portal-kombat" "Name=state,Values=available,pending" \
        --region "$REGION" \
        --query 'TransitGatewayAttachments[*].[TransitGatewayAttachmentId,State,ResourceType,Tags[?Key==`managedBy`].Value|[0]]' \
        --output text 2>/dev/null)

    if [ -n "$orphaned_atts" ]; then
        log_warning "Found potentially orphaned VPC Attachments:"
        echo "$orphaned_atts" | while read -r att_id state resource_type managed_by; do
            log_info "  $att_id (State: $state, Type: $resource_type, ManagedBy: ${managed_by:-unknown})"

            # Check if still in Crossplane
            local in_crossplane=$(kubectl get transitgatewayattachment -A -o json 2>/dev/null | \
                jq -r ".items[] | select(.status.atProvider.transitGatewayAttachmentId==\"$att_id\") | .metadata.name")

            if [ -z "$in_crossplane" ]; then
                log_warning "  → NOT FOUND in Crossplane - likely orphaned"

                if [ "$FORCE" = true ]; then
                    log_info "  → Deleting orphaned VPC Attachment $att_id..."
                    if aws ec2 delete-transit-gateway-vpc-attachment --transit-gateway-attachment-id "$att_id" --region "$REGION" &>> "$LOG_FILE"; then
                        log_success "  → Deleted $att_id"
                    else
                        log_error "  → Failed to delete $att_id"
                    fi
                fi
            else
                log_info "  → Found in Crossplane as: $in_crossplane"
            fi
        done
    else
        log_success "No orphaned VPC Attachments found"
    fi

    # Check for orphaned Route Tables
    log_step "Checking for orphaned Route Tables..."
    local orphaned_rts=$(aws ec2 describe-transit-gateway-route-tables \
        --filters "Name=tag:project,Values=portal-kombat" "Name=state,Values=available,pending" \
        --region "$REGION" \
        --query 'TransitGatewayRouteTables[*].[TransitGatewayRouteTableId,State,Tags[?Key==`managedBy`].Value|[0]]' \
        --output text 2>/dev/null)

    if [ -n "$orphaned_rts" ]; then
        log_warning "Found potentially orphaned Route Tables:"
        echo "$orphaned_rts" | while read -r rt_id state managed_by; do
            log_info "  $rt_id (State: $state, ManagedBy: ${managed_by:-unknown})"

            # Check if still in Crossplane
            local in_crossplane=$(kubectl get transitgatewayroutetable -A -o json 2>/dev/null | \
                jq -r ".items[] | select(.status.atProvider.transitGatewayRouteTableId==\"$rt_id\") | .metadata.name")

            if [ -z "$in_crossplane" ]; then
                log_warning "  → NOT FOUND in Crossplane - likely orphaned"

                if [ "$FORCE" = true ]; then
                    log_info "  → Deleting orphaned Route Table $rt_id..."
                    if aws ec2 delete-transit-gateway-route-table --transit-gateway-route-table-id "$rt_id" --region "$REGION" &>> "$LOG_FILE"; then
                        log_success "  → Deleted $rt_id"
                    else
                        log_error "  → Failed to delete $rt_id"
                    fi
                fi
            else
                log_info "  → Found in Crossplane as: $in_crossplane"
            fi
        done
    else
        log_success "No orphaned Route Tables found"
    fi

    if [ "$FORCE" = false ]; then
        log_info ""
        log_info "To automatically delete orphaned resources, run with --force --aws-cleanup"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --verify-only)
                VERIFY_ONLY=true
                shift
                ;;
            --aws-cleanup)
                AWS_CLEANUP=true
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
    print_header "Phase 1 Integration Test Cleanup"
    log_info "Cleanup started: $(date)"
    log_info "Log file: $LOG_FILE"

    # List resources
    if ! list_resources; then
        log_success "Nothing to clean up - environment is already clean"
        exit 0
    fi

    # Verify only mode
    if [ "$VERIFY_ONLY" = true ]; then
        log_info "VERIFY ONLY mode - no resources will be deleted"
        exit 0
    fi

    # AWS cleanup mode
    if [ "$AWS_CLEANUP" = true ]; then
        cleanup_orphaned_aws_resources
        exit 0
    fi

    # Perform cleanup in correct order
    log_info ""
    log_info "Resources will be deleted in the following order:"
    log_info "  1. VPC Attachments (dependent resources)"
    log_info "  2. Route Tables (dependent resources)"
    log_info "  3. Transit Gateways (parent resources)"
    log_info "  4. Connection Secrets (metadata)"
    log_info ""

    if [ "$FORCE" = false ]; then
        read -p "Press Enter to continue or Ctrl+C to cancel..."
    fi

    # Execute cleanup
    delete_attachments
    delete_route_tables
    delete_transit_gateways
    delete_connection_secrets

    # Final verification
    print_header "Cleanup Verification"

    if list_resources &> /dev/null; then
        log_error "Some resources still exist after cleanup"
        log_error "Check log file for details: $LOG_FILE"
        exit 1
    fi

    log_success "All Phase 1 resources successfully deleted"
    log_info "Cleanup completed: $(date)"
    log_info "Full log: $LOG_FILE"

    # Suggest orphaned resource check
    log_info ""
    log_info "To check for orphaned AWS resources, run:"
    log_info "  $(basename "$0") --aws-cleanup"
}

# Run main function
main "$@"
