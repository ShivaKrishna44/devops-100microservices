#!/bin/bash
set -e

echo "=== Installing Prometheus + Grafana Stack ==="

# Create namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values ../kubernetes/monitoring/prometheus-values.yaml \
  --set grafana.service.type=LoadBalancer \
  --wait --timeout 10m

echo ""
echo "=== Monitoring Stack Installed ==="
echo "Grafana URL:"
kubectl -n monitoring get svc prometheus-grafana -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo ""
echo "Grafana credentials: admin / admin123"
echo ""
echo "Prometheus URL:"
kubectl -n monitoring get svc prometheus-kube-prometheus-prometheus -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
echo ""
