#!/bin/bash
set -e

# ArgoCD Application Naming Validation Script
# This script validates the current state of ArgoCD applications
# and checks their health status before proceeding with renaming operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=================================================="
echo "ArgoCD Application Naming Validation"
echo "=================================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if argocd namespace exists
if ! kubectl get namespace argocd &> /dev/null; then
    echo -e "${RED}✗ ArgoCD namespace not found. Is ArgoCD installed?${NC}"
    exit 1
fi

echo -e "${BLUE}Kubernetes Context: $(kubectl config current-context)${NC}"
echo ""

# Function to get application health status
get_app_health() {
    local app=$1
    kubectl get application "${app}" -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown"
}

# Function to get application sync status
get_app_sync() {
    local app=$1
    kubectl get application "${app}" -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown"
}

# Function to get application source path
get_app_path() {
    local app=$1
    kubectl get application "${app}" -n argocd -o jsonpath='{.spec.source.path}' 2>/dev/null || echo "N/A"
}

# Check if ArgoCD server is healthy
echo -e "${YELLOW}Checking ArgoCD Server Status...${NC}"
if kubectl get deployment argocd-server -n argocd &> /dev/null; then
    REPLICAS=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}')
    if [ "$REPLICAS" -ge 1 ]; then
        echo -e "${GREEN}✓ ArgoCD server is running (${REPLICAS} replicas ready)${NC}"
    else
        echo -e "${RED}✗ ArgoCD server is not ready${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ ArgoCD server deployment not found${NC}"
    exit 1
fi
echo ""

# List all applications
echo -e "${YELLOW}Checking ArgoCD Applications...${NC}"
APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$APPS" ]; then
    echo -e "${YELLOW}⚠ No applications found${NC}"
    exit 0
fi

# Count applications
APP_COUNT=$(echo "$APPS" | wc -w | tr -d ' ')
echo -e "${CYAN}Found ${APP_COUNT} applications${NC}"
echo ""

# Validate each application
HEALTHY_COUNT=0
DEGRADED_COUNT=0
SYNCED_COUNT=0
OUTOFSYNC_COUNT=0

echo "Application Status:"
echo "===================="
printf "%-40s %-12s %-12s %s\n" "NAME" "HEALTH" "SYNC" "PATH"
echo "--------------------------------------------------------------------------------"

for app in $APPS; do
    HEALTH=$(get_app_health "$app")
    SYNC=$(get_app_sync "$app")
    PATH=$(get_app_path "$app")

    # Color code health status
    if [ "$HEALTH" = "Healthy" ]; then
        HEALTH_COLOR="${GREEN}"
        HEALTHY_COUNT=$((HEALTHY_COUNT + 1))
    elif [ "$HEALTH" = "Progressing" ]; then
        HEALTH_COLOR="${YELLOW}"
    else
        HEALTH_COLOR="${RED}"
        DEGRADED_COUNT=$((DEGRADED_COUNT + 1))
    fi

    # Color code sync status
    if [ "$SYNC" = "Synced" ]; then
        SYNC_COLOR="${GREEN}"
        SYNCED_COUNT=$((SYNCED_COUNT + 1))
    else
        SYNC_COLOR="${YELLOW}"
        OUTOFSYNC_COUNT=$((OUTOFSYNC_COUNT + 1))
    fi

    printf "%-40s ${HEALTH_COLOR}%-12s${NC} ${SYNC_COLOR}%-12s${NC} %s\n" \
        "$app" "$HEALTH" "$SYNC" "$PATH"
done

echo ""
echo "Summary:"
echo "===================="
echo -e "Total Applications: ${CYAN}${APP_COUNT}${NC}"
echo -e "Healthy: ${GREEN}${HEALTHY_COUNT}${NC}"
echo -e "Degraded/Other: ${RED}${DEGRADED_COUNT}${NC}"
echo -e "Synced: ${GREEN}${SYNCED_COUNT}${NC}"
echo -e "OutOfSync: ${YELLOW}${OUTOFSYNC_COUNT}${NC}"
echo ""

# Check for naming conflicts
echo -e "${YELLOW}Checking for naming conflicts...${NC}"
CONFLICT_FOUND=0

# Check for similar names that might cause confusion
declare -A APP_PREFIXES
for app in $APPS; do
    # Extract prefix (everything before first dash)
    PREFIX=$(echo "$app" | cut -d'-' -f1)

    if [ -n "${APP_PREFIXES[$PREFIX]}" ]; then
        APP_PREFIXES[$PREFIX]="${APP_PREFIXES[$PREFIX]} $app"
    else
        APP_PREFIXES[$PREFIX]="$app"
    fi
done

for prefix in "${!APP_PREFIXES[@]}"; do
    COUNT=$(echo "${APP_PREFIXES[$prefix]}" | wc -w | tr -d ' ')
    if [ "$COUNT" -gt 1 ]; then
        echo -e "${YELLOW}⚠ Multiple applications with prefix '${prefix}':${NC}"
        for app in ${APP_PREFIXES[$prefix]}; do
            echo "    - $app"
        done
        CONFLICT_FOUND=1
    fi
done

if [ "$CONFLICT_FOUND" -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious naming conflicts found${NC}"
fi
echo ""

# Check ArgoCD Projects
echo -e "${YELLOW}Checking ArgoCD Projects...${NC}"
PROJECTS=$(kubectl get appprojects -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -z "$PROJECTS" ]; then
    echo -e "${YELLOW}⚠ No projects found${NC}"
else
    PROJECT_COUNT=$(echo "$PROJECTS" | wc -w | tr -d ' ')
    echo -e "${CYAN}Found ${PROJECT_COUNT} projects:${NC}"
    for project in $PROJECTS; do
        echo "  - $project"
    done
fi
echo ""

# Overall validation result
echo "=================================================="
if [ "$DEGRADED_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Validation Complete with Warnings${NC}"
    echo ""
    echo -e "${YELLOW}${DEGRADED_COUNT} application(s) are not healthy.${NC}"
    echo "Consider investigating unhealthy applications before proceeding."
    exit 0
else
    echo -e "${GREEN}✓ Validation Complete - All Systems Healthy${NC}"
    echo ""
    echo "All applications are healthy. Safe to proceed with naming changes."
fi
echo "=================================================="
echo ""

# Provide helpful commands
echo "Useful commands:"
echo "  View application details: kubectl describe application <app-name> -n argocd"
echo "  View application events: kubectl get events -n argocd --field-selector involvedObject.name=<app-name>"
echo "  Force sync: kubectl patch application <app-name> -n argocd --type merge -p '{\"operation\":{\"initiatedBy\":{\"username\":\"admin\"},\"sync\":{}}}'"
echo "  View logs: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50"
echo ""
