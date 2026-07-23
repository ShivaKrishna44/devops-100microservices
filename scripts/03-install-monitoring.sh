#!/bin/bash
set -e

echo "=== Installing Prometheus + Grafana Stack ==="

# Create namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Add Helm repo
helm.exe repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm.exe repo update

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Install kube-prometheus-stack
helm.exe upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values ${PROJECT_DIR}/kubernetes/monitoring/prometheus-values.yaml \
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
