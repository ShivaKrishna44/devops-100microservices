#!/bin/bash
set -e


# aws eks update-kubeconfig --name devops-100ms-cluster --region us-east-1

echo "=== Installing AWS ALB Ingress Controller ==="

# Add Helm repo
helm.exe repo add eks https://aws.github.io/eks-charts
helm.exe repo update

# Variables — set these to match your environment
CLUSTER_NAME="devops-100ms-cluster"
REGION="us-east-1"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=*devops-100ms*" --query "Vpcs[0].VpcId" --output text --region $REGION)

echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "VPC: $VPC_ID"

# Install ALB controller
helm.exe upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=${REGION} \
  --set vpcId=${VPC_ID}

echo "=== ALB Controller installed ==="
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
