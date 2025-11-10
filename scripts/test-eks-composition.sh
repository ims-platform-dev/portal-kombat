#!/usr/bin/env bash
# ==============================================================================
# EKS Composition Testing Script
# ==============================================================================
# This script validates the EKS production composition using crossplane beta render
# to test the composition offline without deploying to AWS.
#
# Prerequisites:
#   - crossplane CLI installed (https://docs.crossplane.io/latest/cli/)
#   - kubectl installed
#   - Access to the Portal Kombat repository
#
# Usage:
#   ./scripts/test-eks-composition.sh
#   ./scripts/test-eks-composition.sh --verbose
#   ./scripts/test-eks-composition.sh --example eks-cluster-comprehensive.yaml
#
# What this script does:
#   1. Validates composition syntax and structure
#   2. Renders the minimal example claim to check resource generation
#   3. Validates expected resource counts
#   4. Checks for required labels on all resources
#   5. Validates connection secret keys
#   6. Reports any issues or warnings
# ==============================================================================

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
XRD_FILE="${REPO_ROOT}/infra-definitions/xrds/compute/xrd-eks-cluster.yaml"
COMPOSITION_FILE="${REPO_ROOT}/infra-definitions/compositions/compute/eks-production.yaml"
DEFAULT_EXAMPLE="${REPO_ROOT}/examples/compute/eks-cluster-minimal.yaml"
VERBOSE=false
EXAMPLE_FILE=""

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Expected resource counts
EXPECTED_IAM_ROLES_MIN=2              # cluster + node
EXPECTED_IAM_ROLES_MAX=6              # cluster + node + 4 pod identity roles
EXPECTED_POLICY_ATTACHMENTS_MIN=3    # cluster policies + node policies
EXPECTED_POLICY_ATTACHMENTS_MAX=10   # + pod identity policy attachments
EXPECTED_EKS_CLUSTERS=1
EXPECTED_LAUNCH_TEMPLATES_MIN=1
EXPECTED_NODE_GROUPS_MIN=1
EXPECTED_ADDONS_MIN=4                # coredns, vpc-cni, kube-proxy, pod-identity-agent
EXPECTED_ADDONS_MAX=5                # + efs-csi (optional)

# Required labels
REQUIRED_LABEL_KEY="portal-kombat.io/eks-component"

# Expected connection secret keys
EXPECTED_SECRET_KEYS=("kubeconfig" "endpoint" "ca-certificate-authority-data" "oidc-issuer-url" "cluster-name" "region")

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    echo -e "\n${BLUE}===================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    local all_ok=true

    # Check crossplane CLI
    if command -v crossplane &> /dev/null; then
        local version=$(crossplane version 2>/dev/null || echo "unknown")
        print_success "crossplane CLI found (version: ${version})"
    else
        print_error "crossplane CLI not found. Install from: https://docs.crossplane.io/latest/cli/"
        all_ok=false
    fi

    # Check kubectl
    if command -v kubectl &> /dev/null; then
        local version=$(kubectl version --client --short 2>/dev/null | head -n1 || echo "unknown")
        print_success "kubectl found (${version})"
    else
        print_warning "kubectl not found (optional, but recommended)"
    fi

    # Check required files exist
    if [[ -f "${XRD_FILE}" ]]; then
        print_success "XRD file found: ${XRD_FILE}"
    else
        print_error "XRD file not found: ${XRD_FILE}"
        all_ok=false
    fi

    if [[ -f "${COMPOSITION_FILE}" ]]; then
        print_success "Composition file found: ${COMPOSITION_FILE}"
    else
        print_error "Composition file not found: ${COMPOSITION_FILE}"
        all_ok=false
    fi

    if [[ -f "${EXAMPLE_FILE}" ]]; then
        print_success "Example claim file found: ${EXAMPLE_FILE}"
    else
        print_error "Example claim file not found: ${EXAMPLE_FILE}"
        all_ok=false
    fi

    if [[ "${all_ok}" != "true" ]]; then
        print_error "Prerequisites check failed. Please install missing dependencies."
        exit 1
    fi

    print_success "All prerequisites met"
}

validate_composition_syntax() {
    print_header "Validating Composition Syntax"

    # Validate YAML syntax
    if command -v yamllint &> /dev/null; then
        if yamllint -d relaxed "${COMPOSITION_FILE}" &> /dev/null; then
            print_success "Composition YAML syntax is valid"
        else
            print_error "Composition YAML syntax validation failed"
            yamllint -d relaxed "${COMPOSITION_FILE}"
            exit 1
        fi
    else
        print_warning "yamllint not installed, skipping YAML syntax validation"
    fi

    # Validate Kubernetes resource structure
    if kubectl apply --dry-run=client -f "${COMPOSITION_FILE}" &> /dev/null; then
        print_success "Composition Kubernetes resource structure is valid"
    else
        print_error "Composition Kubernetes resource validation failed"
        kubectl apply --dry-run=client -f "${COMPOSITION_FILE}"
        exit 1
    fi
}

render_composition() {
    print_header "Rendering Composition with Example Claim"

    local temp_dir=$(mktemp -d)
    local output_file="${temp_dir}/rendered.yaml"

    print_info "Rendering: ${EXAMPLE_FILE}"
    print_info "Using XRD: ${XRD_FILE}"
    print_info "Using Composition: ${COMPOSITION_FILE}"

    # Combine XRD and Composition for rendering
    cat "${XRD_FILE}" > "${temp_dir}/xrd-and-composition.yaml"
    echo "---" >> "${temp_dir}/xrd-and-composition.yaml"
    cat "${COMPOSITION_FILE}" >> "${temp_dir}/xrd-and-composition.yaml"

    # Render the composition
    if crossplane beta render "${EXAMPLE_FILE}" "${temp_dir}/xrd-and-composition.yaml" > "${output_file}" 2>&1; then
        print_success "Composition rendered successfully"
    else
        print_error "Composition rendering failed"
        cat "${output_file}"
        rm -rf "${temp_dir}"
        exit 1
    fi

    if [[ "${VERBOSE}" == "true" ]]; then
        echo ""
        print_info "Rendered output:"
        cat "${output_file}"
        echo ""
    fi

    # Return the output file path for further validation
    echo "${output_file}"
}

count_resources() {
    local output_file=$1
    local resource_type=$2

    # Count resources by apiVersion and kind
    grep -c "kind: ${resource_type}" "${output_file}" 2>/dev/null || echo "0"
}

validate_resource_counts() {
    print_header "Validating Resource Counts"

    local output_file=$1
    local all_ok=true

    # Count IAM Roles
    local iam_roles=$(count_resources "${output_file}" "Role")
    if [[ ${iam_roles} -ge ${EXPECTED_IAM_ROLES_MIN} ]] && [[ ${iam_roles} -le ${EXPECTED_IAM_ROLES_MAX} ]]; then
        print_success "IAM Roles: ${iam_roles} (expected: ${EXPECTED_IAM_ROLES_MIN}-${EXPECTED_IAM_ROLES_MAX})"
    else
        print_error "IAM Roles: ${iam_roles} (expected: ${EXPECTED_IAM_ROLES_MIN}-${EXPECTED_IAM_ROLES_MAX})"
        all_ok=false
    fi

    # Count RolePolicyAttachments
    local policy_attachments=$(count_resources "${output_file}" "RolePolicyAttachment")
    if [[ ${policy_attachments} -ge ${EXPECTED_POLICY_ATTACHMENTS_MIN} ]] && [[ ${policy_attachments} -le ${EXPECTED_POLICY_ATTACHMENTS_MAX} ]]; then
        print_success "RolePolicyAttachments: ${policy_attachments} (expected: ${EXPECTED_POLICY_ATTACHMENTS_MIN}-${EXPECTED_POLICY_ATTACHMENTS_MAX})"
    else
        print_error "RolePolicyAttachments: ${policy_attachments} (expected: ${EXPECTED_POLICY_ATTACHMENTS_MIN}-${EXPECTED_POLICY_ATTACHMENTS_MAX})"
        all_ok=false
    fi

    # Count EKS Clusters
    local eks_clusters=$(count_resources "${output_file}" "Cluster")
    if [[ ${eks_clusters} -eq ${EXPECTED_EKS_CLUSTERS} ]]; then
        print_success "EKS Clusters: ${eks_clusters} (expected: ${EXPECTED_EKS_CLUSTERS})"
    else
        print_error "EKS Clusters: ${eks_clusters} (expected: ${EXPECTED_EKS_CLUSTERS})"
        all_ok=false
    fi

    # Count LaunchTemplates
    local launch_templates=$(count_resources "${output_file}" "LaunchTemplate")
    if [[ ${launch_templates} -ge ${EXPECTED_LAUNCH_TEMPLATES_MIN} ]]; then
        print_success "LaunchTemplates: ${launch_templates} (expected: >=${EXPECTED_LAUNCH_TEMPLATES_MIN})"
    else
        print_error "LaunchTemplates: ${launch_templates} (expected: >=${EXPECTED_LAUNCH_TEMPLATES_MIN})"
        all_ok=false
    fi

    # Count NodeGroups
    local node_groups=$(count_resources "${output_file}" "NodeGroup")
    if [[ ${node_groups} -ge ${EXPECTED_NODE_GROUPS_MIN} ]]; then
        print_success "NodeGroups: ${node_groups} (expected: >=${EXPECTED_NODE_GROUPS_MIN})"
    else
        print_error "NodeGroups: ${node_groups} (expected: >=${EXPECTED_NODE_GROUPS_MIN})"
        all_ok=false
    fi

    # Count Addons
    local addons=$(count_resources "${output_file}" "Addon")
    if [[ ${addons} -ge ${EXPECTED_ADDONS_MIN} ]] && [[ ${addons} -le ${EXPECTED_ADDONS_MAX} ]]; then
        print_success "Addons: ${addons} (expected: ${EXPECTED_ADDONS_MIN}-${EXPECTED_ADDONS_MAX})"
    else
        print_warning "Addons: ${addons} (expected: ${EXPECTED_ADDONS_MIN}-${EXPECTED_ADDONS_MAX}, may vary based on configuration)"
    fi

    # Total resource count
    local total_resources=$(grep -c "^kind:" "${output_file}" 2>/dev/null || echo "0")
    print_info "Total managed resources: ${total_resources}"

    if [[ "${all_ok}" != "true" ]]; then
        print_error "Resource count validation failed"
        return 1
    fi

    print_success "All resource counts are within expected ranges"
    return 0
}

validate_labels() {
    print_header "Validating Required Labels"

    local output_file=$1
    local all_ok=true

    # Extract all resource kinds that should have the label
    local resource_kinds=("Role" "RolePolicyAttachment" "Cluster" "LaunchTemplate" "NodeGroup" "Addon")

    print_info "Checking for label: ${REQUIRED_LABEL_KEY}"

    # Check if resources have the required label
    for kind in "${resource_kinds[@]}"; do
        local count=$(grep -A 5 "kind: ${kind}" "${output_file}" | grep -c "${REQUIRED_LABEL_KEY}" || echo "0")
        local total=$(count_resources "${output_file}" "${kind}")

        if [[ ${total} -gt 0 ]]; then
            if [[ ${count} -ge ${total} ]]; then
                print_success "${kind}: ${count}/${total} resources have required label"
            else
                print_warning "${kind}: ${count}/${total} resources have required label (some may be missing)"
            fi
        fi
    done

    print_success "Label validation complete"
}

validate_connection_secret() {
    print_header "Validating Connection Secret Keys"

    local output_file=$1
    local all_ok=true

    # Check XRD for connection secret keys
    print_info "Checking XRD for connection secret keys"

    for key in "${EXPECTED_SECRET_KEYS[@]}"; do
        if grep -q "- ${key}" "${XRD_FILE}"; then
            print_success "Connection secret key defined: ${key}"
        else
            print_error "Missing connection secret key: ${key}"
            all_ok=false
        fi
    done

    if [[ "${all_ok}" != "true" ]]; then
        print_error "Connection secret validation failed"
        return 1
    fi

    print_success "All required connection secret keys are defined"
    return 0
}

print_summary() {
    print_header "Test Summary"

    print_success "Composition testing completed successfully"
    echo ""
    print_info "Next steps:"
    echo "  1. Review the rendered output (use --verbose flag)"
    echo "  2. Deploy to a test cluster: kubectl apply -f ${EXAMPLE_FILE}"
    echo "  3. Monitor deployment: kubectl get ekscluster -w"
    echo "  4. Check resource status: kubectl describe ekscluster <name>"
    echo ""
    print_info "For troubleshooting, see: docs/eks-composition-troubleshooting.md"
}

# ==============================================================================
# Main Script
# ==============================================================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --example|-e)
                EXAMPLE_FILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --verbose, -v          Enable verbose output"
                echo "  --example, -e FILE     Use custom example claim file"
                echo "  --help, -h             Show this help message"
                echo ""
                echo "Example:"
                echo "  $0 --verbose"
                echo "  $0 --example examples/compute/eks-cluster-comprehensive.yaml"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Use default example if not specified
    if [[ -z "${EXAMPLE_FILE}" ]]; then
        EXAMPLE_FILE="${DEFAULT_EXAMPLE}"
    fi

    print_header "EKS Composition Testing Script"
    print_info "Repository: ${REPO_ROOT}"
    print_info "Testing example: ${EXAMPLE_FILE}"

    # Run validation steps
    check_prerequisites
    validate_composition_syntax

    local output_file=$(render_composition)

    validate_resource_counts "${output_file}" || exit 1
    validate_labels "${output_file}"
    validate_connection_secret || exit 1

    # Cleanup
    rm -rf "$(dirname "${output_file}")"

    print_summary
}

main "$@"
