#!/bin/bash
set -e

echo "=== Installing ArgoCD ==="

# Create namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
helm.exe repo add argo https://argoproj.github.io/argo-helm
helm.exe repo update

helm.exe upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set server.extraArgs[0]="--insecure" \
  --set configs.params."server\.insecure"=true \
  --wait

# Get initial admin password
echo ""
echo "=== ArgoCD Installed ==="
echo "Admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "ArgoCD URL:"
kubectl -n argocd get svc argocd-server -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo ""
