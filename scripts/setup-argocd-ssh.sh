#!/bin/bash
set -euo pipefail

# Setup ArgoCD SSH Authentication for GitOps Repository
# Usage: ./scripts/setup-argocd-ssh.sh [environment]

ENV="${1:-dev}"
REPO_URL="git@github.com:ims-platform-dev/portal-kombat.git"
SECRET_NAME="portal-kombat-repo"
KEY_PATH="${HOME}/.ssh/argocd-portal-kombat"

echo "🔐 Setting up ArgoCD SSH authentication for ${ENV} environment"

# Step 1: Generate SSH key if it doesn't exist
if [ ! -f "${KEY_PATH}" ]; then
    echo "📝 Generating new SSH key pair..."
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "argocd@portal-kombat" -N ""
    echo "✅ SSH key pair generated at ${KEY_PATH}"
    echo ""
    echo "📋 Public key to add to GitHub Deploy Keys:"
    echo "   Repository Settings > Deploy Keys > Add deploy key"
    echo "   Title: ArgoCD Portal Kombat ${ENV}"
    echo "   Key:"
    cat "${KEY_PATH}.pub"
    echo ""
    read -p "Press Enter after adding the public key to GitHub..."
else
    echo "✅ Using existing SSH key at ${KEY_PATH}"
fi

# Step 2: Get GitHub's SSH host key
echo "🔍 Fetching GitHub SSH host key..."
KNOWN_HOSTS=$(ssh-keyscan -t rsa,ed25519 github.com 2>/dev/null)

# Step 3: Create Kubernetes secret
echo "📦 Creating Kubernetes secret in argocd namespace..."
kubectl create secret generic "${SECRET_NAME}" \
  --namespace argocd \
  --from-literal=type=git \
  --from-literal=url="${REPO_URL}" \
  --from-file=sshPrivateKey="${KEY_PATH}" \
  --from-literal=insecure="false" \
  --from-literal=enableLfs="false" \
  --dry-run=client -o yaml | \
  kubectl label --local -f - \
    argocd.argoproj.io/secret-type=repository \
    --dry-run=client -o yaml | \
  kubectl apply -f -

echo "✅ Secret created successfully"

# Step 4: Verify secret
echo "🔍 Verifying secret..."
kubectl get secret "${SECRET_NAME}" -n argocd -o jsonpath='{.metadata.labels}' | grep -q "argocd.argoproj.io/secret-type" && \
  echo "✅ Secret label verified" || \
  echo "⚠️  Warning: Secret label not found"

# Step 5: Test repository connection
echo "🧪 Testing repository connection..."
echo "   Check ArgoCD UI: Settings > Repositories"
echo "   Or run: argocd repo list"
echo ""
echo "✅ Setup complete!"
echo ""
echo "🎯 Next steps:"
echo "   1. Verify in ArgoCD UI: Settings > Repositories should show 'Successful'"
echo "   2. Deploy root app: kubectl apply -f environments/${ENV}/argocd/root-apps.yaml"
echo "   3. Monitor sync: kubectl get applications -n argocd -w"
