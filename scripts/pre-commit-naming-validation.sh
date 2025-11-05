#!/bin/bash
# Pre-commit hook to validate ArgoCD application naming conventions
#
# This script validates that ArgoCD application files follow the standardized
# naming conventions defined in docs/NAMING_CONVENTIONS.md
#
# Installation:
#   ln -s ../../scripts/pre-commit-naming-validation.sh .git/hooks/pre-commit
#
# Or run manually:
#   ./scripts/pre-commit-naming-validation.sh

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Validating ArgoCD naming conventions..."

validation_failed=0

# Check for app-of-apps file naming (must be plural -apps.yaml)
echo "Checking app-of-apps file naming..."
find environments/*/argocd -name "*-app.yaml" -type f 2>/dev/null | while read file; do
    if [[ ! "$file" =~ -apps\.yaml$ ]]; then
        echo "❌ ERROR: $file uses singular '-app.yaml' instead of plural '-apps.yaml'"
        echo "   App-of-apps files must end with -apps.yaml"
        exit 1
    fi
done

if [ $? -ne 0 ]; then
    validation_failed=1
fi

# Check for valid app-of-apps filenames
echo "Validating app-of-apps filename patterns..."
find environments/*/argocd -name "*-apps.yaml" -type f 2>/dev/null | while read file; do
    basename=$(basename "$file")
    if [[ ! "$basename" =~ ^(root|crossplane-platform|k8s-platform-services|infrastructure-claims|workloads)-apps\.yaml$ ]]; then
        echo "⚠️  WARNING: $file doesn't match standard naming pattern"
        echo "   Expected: {root|crossplane-platform|k8s-platform-services|infrastructure-claims|workloads}-apps.yaml"
        echo "   Current: $basename"
    fi
done

# Validate application names in YAML files have environment prefixes
echo "Checking application names for environment prefixes..."
application_files=$(find environments/*/argocd -name "*.yaml" -type f -exec grep -l "kind: Application" {} \; 2>/dev/null)

if [ -n "$application_files" ]; then
    for file in $application_files; do
        # Extract environment from path
        if [[ "$file" =~ environments/([^/]+)/ ]]; then
            env="${BASH_REMATCH[1]}"

            # Check if application name has environment prefix
            app_name=$(grep -E "^  name:" "$file" | head -1 | awk '{print $2}')
            if [ -n "$app_name" ]; then
                if [[ ! "$app_name" =~ ^${env}- ]]; then
                    echo "⚠️  WARNING: $file application name '$app_name' missing '$env-' prefix"
                fi
            fi
        fi
    done
fi

# Check for old patterns that should be updated
echo "Checking for deprecated patterns..."
old_pattern_count=$(grep -r "root-app\.yaml" environments/*/argocd 2>/dev/null | grep -v "^Binary" | wc -l)
if [ "$old_pattern_count" -gt 0 ]; then
    echo "⚠️  WARNING: Found $old_pattern_count references to old 'root-app.yaml' pattern"
    echo "   Should be 'root-apps.yaml' per naming conventions"
fi

# Check for application-apps.yaml pattern (redundant)
redundant_pattern=$(find environments/*/argocd -name "*-application-apps.yaml" -o -name "*-application.yaml" 2>/dev/null)
if [ -n "$redundant_pattern" ]; then
    echo "⚠️  WARNING: Found files with redundant 'application' in name:"
    echo "$redundant_pattern"
    echo "   Simplify to just the purpose (e.g., 'platform-apps.yaml' not 'platform-application-apps.yaml')"
fi

if [ $validation_failed -eq 0 ]; then
    echo "✅ Naming validation complete - no critical errors"
    exit 0
else
    echo "❌ Naming validation failed - fix errors before committing"
    exit 1
fi
