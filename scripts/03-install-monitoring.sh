#!/bin/bash
set -e

echo "=== Installing Prometheus + Grafana Stack ==="

# Create namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repo
helm.exe repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm.exe repo update

# Install kube-prometheus-stack (no persistent storage for lab environment)
helm.exe upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=LoadBalancer \
  --set prometheus.prometheusSpec.retention=2d \
  --set prometheus.prometheusSpec.storageSpec="" \
  --set alertmanager.alertmanagerSpec.storage="" \
  --set grafana.persistence.enabled=false \
  --timeout 10m

echo ""
echo "=== Monitoring Stack Installed ==="
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80"
echo "  Open: http://localhost:3000"
echo "  User: admin | Password: admin123"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090"
echo "  Open: http://localhost:9090"
echo ""
