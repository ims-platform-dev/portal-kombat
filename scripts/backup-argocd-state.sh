#!/bin/bash
set -e

# ArgoCD State Backup Script
# This script exports all ArgoCD applications, projects, and configurations to YAML files
# for backup purposes before making structural changes

BACKUP_DIR="backups/argocd-$(date +%Y%m%d-%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================================="
echo "ArgoCD State Backup"
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

# Create backup directory
BACKUP_PATH="${REPO_ROOT}/${BACKUP_DIR}"
mkdir -p "${BACKUP_PATH}/applications"
mkdir -p "${BACKUP_PATH}/projects"
mkdir -p "${BACKUP_PATH}/configmaps"
mkdir -p "${BACKUP_PATH}/secrets"

echo -e "${BLUE}Creating backup in: ${BACKUP_PATH}${NC}"
echo ""

# Backup Applications
echo -e "${YELLOW}Backing up ArgoCD Applications...${NC}"
APPS=$(kubectl get applications -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$APPS" ]; then
    echo -e "${YELLOW}⚠ No applications found${NC}"
else
    APP_COUNT=0
    for app in $APPS; do
        echo "  → Exporting application: ${app}"
        kubectl get application "${app}" -n argocd -o yaml > "${BACKUP_PATH}/applications/${app}.yaml"
        APP_COUNT=$((APP_COUNT + 1))
    done
    echo -e "${GREEN}✓ Backed up ${APP_COUNT} applications${NC}"
fi
echo ""

# Backup Projects
echo -e "${YELLOW}Backing up ArgoCD Projects...${NC}"
PROJECTS=$(kubectl get appprojects -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$PROJECTS" ]; then
    echo -e "${YELLOW}⚠ No projects found${NC}"
else
    PROJECT_COUNT=0
    for project in $PROJECTS; do
        echo "  → Exporting project: ${project}"
        kubectl get appproject "${project}" -n argocd -o yaml > "${BACKUP_PATH}/projects/${project}.yaml"
        PROJECT_COUNT=$((PROJECT_COUNT + 1))
    done
    echo -e "${GREEN}✓ Backed up ${PROJECT_COUNT} projects${NC}"
fi
echo ""

# Backup ConfigMaps
echo -e "${YELLOW}Backing up ArgoCD ConfigMaps...${NC}"
CONFIGMAPS="argocd-cm argocd-rbac-cm argocd-ssh-known-hosts-cm argocd-tls-certs-cm"
CM_COUNT=0

for cm in $CONFIGMAPS; do
    if kubectl get configmap "${cm}" -n argocd &> /dev/null; then
        echo "  → Exporting configmap: ${cm}"
        kubectl get configmap "${cm}" -n argocd -o yaml > "${BACKUP_PATH}/configmaps/${cm}.yaml"
        CM_COUNT=$((CM_COUNT + 1))
    fi
done
echo -e "${GREEN}✓ Backed up ${CM_COUNT} configmaps${NC}"
echo ""

# Backup Secret names (not values)
echo -e "${YELLOW}Backing up ArgoCD Secret metadata...${NC}"
SECRETS=$(kubectl get secrets -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -z "$SECRETS" ]; then
    echo -e "${YELLOW}⚠ No secrets found${NC}"
else
    SECRET_COUNT=0
    for secret in $SECRETS; do
        echo "  → Exporting secret metadata: ${secret}"
        # Export only metadata, not actual secret values
        kubectl get secret "${secret}" -n argocd -o yaml | \
            sed '/data:/,$d' > "${BACKUP_PATH}/secrets/${secret}-metadata.yaml"
        SECRET_COUNT=$((SECRET_COUNT + 1))
    done
    echo -e "${GREEN}✓ Backed up ${SECRET_COUNT} secret metadata entries${NC}"
fi
echo ""

# Create backup manifest
cat > "${BACKUP_PATH}/backup-manifest.txt" <<EOF
ArgoCD State Backup
===================
Timestamp: $(date)
Backup Directory: ${BACKUP_PATH}

Applications: ${APP_COUNT:-0}
Projects: ${PROJECT_COUNT:-0}
ConfigMaps: ${CM_COUNT:-0}
Secrets (metadata only): ${SECRET_COUNT:-0}

Kubernetes Context: $(kubectl config current-context)
ArgoCD Version: $(kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
EOF

echo "=================================================="
echo -e "${GREEN}Backup Complete!${NC}"
echo "=================================================="
echo ""
echo "Backup location: ${BACKUP_PATH}"
echo ""
echo "Contents:"
echo "  - Applications: ${BACKUP_PATH}/applications/"
echo "  - Projects: ${BACKUP_PATH}/projects/"
echo "  - ConfigMaps: ${BACKUP_PATH}/configmaps/"
echo "  - Secrets (metadata): ${BACKUP_PATH}/secrets/"
echo "  - Manifest: ${BACKUP_PATH}/backup-manifest.txt"
echo ""
echo "To restore from this backup:"
echo "  kubectl apply -f ${BACKUP_PATH}/projects/"
echo "  kubectl apply -f ${BACKUP_PATH}/applications/"
echo ""
