#!/bin/bash
set -e

echo "=== Installing AWS ALB Ingress Controller ==="

# Add Helm repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Get ALB controller role ARN from terraform output
ALB_ROLE_ARN=$(cd ../terraform && terraform output -raw alb_controller_role_arn)
CLUSTER_NAME=$(cd ../terraform && terraform output -raw cluster_name)
REGION=$(cd ../terraform && terraform output -raw region)
VPC_ID=$(cd ../terraform && terraform output -raw vpc_id)

# Install ALB controller
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${ALB_ROLE_ARN} \
  --set region=${REGION} \
  --set vpcId=${VPC_ID}

echo "=== ALB Controller installed ==="
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
