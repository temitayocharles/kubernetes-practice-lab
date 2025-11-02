#!/bin/bash

# GitHub Repository Setup Script
# This script will help you create and push the Kubernetes Practice Lab to GitHub

set -e

REPO_NAME="kubernetes-practice-lab"
GITHUB_USERNAME="temitayocharles"
REPO_DIR="/Volumes/512-B/smart-kubernetes-cluster"

echo "🚀 GitHub Repository Setup for Kubernetes Practice Lab"
echo "=================================================="
echo ""

# Step 1: Check if git is initialized
cd "$REPO_DIR"
if [ ! -d ".git" ]; then
    echo "❌ Git not initialized. Run: git init"
    exit 1
fi

# Step 2: Check if files are committed
if ! git log --oneline -1 &>/dev/null; then
    echo "📝 Creating initial commit..."
    git add .
    git commit -m "Initial commit: Kubernetes Practice Lab with 12 phases

- 12 progressive practice phases (6-7 hours total)
- Core phases (1-8): Deployments, Services, ConfigMaps, Updates, Ingress, Storage
- Advanced phases (9-10): Labels mastery, Service types
- Security phases (11-12): RBAC, NetworkPolicies, Pod Security
- Local cluster setup script (local-k8s.sh)
- Comprehensive documentation and guides
- Metrics-server RBAC fix included"
else
    echo "✅ Git repository already has commits"
fi

# Step 3: Show instructions for GitHub
echo ""
echo "📋 Next Steps:"
echo "=============="
echo ""
echo "1. Create GitHub repository manually:"
echo "   - Go to: https://github.com/new"
echo "   - Repository name: $REPO_NAME"
echo "   - Description: Comprehensive Kubernetes practice lab with 12 phases covering deployments, services, RBAC, and network security"
echo "   - Public repository (recommended for portfolio)"
echo "   - DO NOT initialize with README (we already have one)"
echo "   - Click 'Create repository'"
echo ""
echo "2. Push your code:"
echo "   git branch -M main"
echo "   git remote add origin https://github.com/$GITHUB_USERNAME/$REPO_NAME.git"
echo "   git push -u origin main"
echo ""
echo "3. Verify repository:"
echo "   https://github.com/$GITHUB_USERNAME/$REPO_NAME"
echo ""
echo "4. Optional: Add repository topics on GitHub"
echo "   - kubernetes"
echo "   - k8s"
echo "   - practice-lab"
echo "   - learning"
echo "   - rbac"
echo "   - network-security"
echo "   - devops"
echo ""
echo "✨ Your repository will be ready to share!"
