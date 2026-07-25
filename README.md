# DevOps 100 Microservices — Production Issues Lab

A production-grade microservices platform on EKS for practicing real-world troubleshooting.

## Architecture

```
AWS Cloud (us-east-1)
├── VPC (3 AZs, public + private subnets)
├── EKS Cluster (v1.31, 3 nodes t3.medium)
│   ├── Namespace: production
│   │   ├── user-service (2 replicas)
│   │   ├── order-service (2 replicas)
│   │   ├── payment-service (2 replicas)
│   │   └── notification-service (2 replicas)
│   ├── Namespace: monitoring
│   │   ├── Prometheus (metrics collection)
│   │   ├── Grafana (dashboards + alerting)
│   │   ├── AlertManager (alert routing)
│   │   └── Node Exporter (per-node metrics)
│   └── Namespace: argocd
│       └── ArgoCD (GitOps deployments)
└── IAM (IRSA for EBS CSI, ALB Controller)
```

## Quick Start

### 1. Deploy Infrastructure
```bash
cd terraform
terraform init
terraform apply

# Update kubeconfig
aws eks update-kubeconfig --name devops-100ms-cluster --region us-east-1
kubectl get nodes
```

### 2. Install Monitoring (Prometheus + Grafana)
```bash
# From project root
bash scripts/03-install-monitoring.sh


#aws eks update-kubeconfig --region us-east-1 --name devops-100ms-cluster

# Or manually:
helm.exe repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm.exe repo update
kubectl create namespace monitoring
helm.exe upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=LoadBalancer \
  --set grafana.adminPassword=admin123
```

### 3. Install ArgoCD
```bash
bash scripts/02-install-argocd.sh

kubectl apply -f kubernetes/argocd/apps/ -n argocd

=== ArgoCD Installed ===
Admin password:
uFQWyJDqvOIU7pSf

ArgoCD URL:
a1c646173b7a3452391027316b16965f-2044187277.us-east-1.elb.amazonaws.com

# Or manually:
kubectl create namespace argocd
helm.exe repo add argo https://argoproj.github.io/argo-helm
helm.exe upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --set server.service.type=LoadBalancer \
  --set configs.params."server\.insecure"=true
```

### 4. Deploy Applications
```bash
kubectl create namespace production

kubectl create deployment user-service --image=nginx:alpine --replicas=2 -n production
kubectl create deployment order-service --image=nginx:alpine --replicas=2 -n production
kubectl create deployment payment-service --image=nginx:alpine --replicas=2 -n production
kubectl create deployment notification-service --image=nginx:alpine --replicas=2 -n production

# Set resources (needed for metrics + HPA)
kubectl set resources deployment/user-service -n production --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
kubectl set resources deployment/order-service -n production --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
kubectl set resources deployment/payment-service -n production --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
kubectl set resources deployment/notification-service -n production --requests=cpu=50m,memory=64Mi --limits=cpu=200m,memory=128Mi
```

### 5. Access Dashboards
```bash
# Grafana (metrics + dashboards)
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# Open: http://localhost:3000 (admin / prom-operator)

# Prometheus (raw queries)
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n monitoring 9090:9090
# Open: http://localhost:9090

# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: http://localhost:8080
# Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Production Issues Lab

### Issue 1: ImagePullBackOff
```bash
# Break
kubectl set image deployment/user-service nginx=nginx:nonexistent-tag -n production

# Troubleshoot
kubectl get pods -n production -l app=user-service
kubectl describe pod -n production -l app=user-service

# Fix
kubectl set image deployment/user-service nginx=nginx:alpine -n production
```

### Issue 2: CrashLoopBackOff
```bash
# Break (busybox exits immediately — no long-running process)
kubectl set image deployment/order-service nginx=busybox:latest -n production

# Troubleshoot
kubectl get pods -n production -l app=order-service
kubectl logs -n production -l app=order-service
# Empty logs = container exits before writing anything. Check exit code:
kubectl describe pod -n production -l app=order-service | findstr "Exit Code"

# Fix
kubectl rollout undo deployment/order-service -n production
```

### Issue 3: OOMKilled
```bash
# Break (memory too low)
kubectl set resources deployment/payment-service -n production --requests=memory=2Mi --limits=memory=2Mi

# Troubleshoot
kubectl describe pod -n production -l app=payment-service | findstr "OOM"
# Exit code 137 = OOMKilled

# Fix
kubectl set resources deployment/payment-service -n production --requests=memory=64Mi --limits=memory=128Mi
```

### Issue 4: Pod Stuck in Pending (Insufficient Resources)
```bash
# Break (request more CPU than nodes have)
kubectl set resources deployment/notification-service -n production --requests=cpu=8

# Troubleshoot
kubectl get pods -n production -l app=notification-service
kubectl describe pod -n production -l app=notification-service
# Events: "Insufficient cpu"

# Fix
kubectl set resources deployment/notification-service -n production --requests=cpu=50m
```

### Issue 5: Service Outage (5xx to dependent services)
```bash
# Break
kubectl scale deployment/payment-service --replicas=0 -n production

# Troubleshoot
kubectl get pods -n production -l app=payment-service
kubectl get endpoints payment-service -n production  # Empty = no backends

# Fix
kubectl scale deployment/payment-service --replicas=2 -n production
```

### Issue 6: Rolling Update Safety (Bad deploy doesn't kill old pods)
```bash
# Break with bad image — notice old pods STAY running
kubectl set image deployment/user-service nginx=nginx:broken-v99 -n production

# Observe
kubectl get pods -n production -l app=user-service
# Old pods: Running | New pod: ImagePullBackOff
# Users NOT affected — old pods still serve traffic

# Fix
kubectl rollout undo deployment/user-service -n production
```

---

## Troubleshooting Commands Cheat Sheet

```bash
# Pod status
kubectl get pods -n production
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production
kubectl logs <pod-name> -n production --previous  # crashed container logs

# Resource usage
kubectl top pods -n production
kubectl top nodes

# Events (sorted by time)
kubectl get events -n production --sort-by=.metadata.creationTimestamp

# Service connectivity
kubectl get endpoints <service-name> -n production
kubectl exec deploy/order-service -n production -- curl -s http://payment-service/

# Rollback
kubectl rollout undo deployment/<name> -n production
kubectl rollout status deployment/<name> -n production
kubectl rollout history deployment/<name> -n production

# HPA
kubectl get hpa -n production
kubectl describe hpa <name> -n production

# Node issues
kubectl get nodes
kubectl describe node <node-name>
kubectl drain <node-name> --ignore-daemonsets
```

---

## Known Issues & Fixes

### kubeconfig stale after cluster recreate
```bash
aws eks update-kubeconfig --name devops-100ms-cluster --region us-east-1
```

### ALB Controller webhook blocking installs
```bash
kubectl delete validatingwebhookconfiguration aws-load-balancer-webhook
kubectl delete mutatingwebhookconfiguration aws-load-balancer-webhook
```

### Grafana "No data" — fix Prometheus data source
```bash
# Get correct Prometheus service name
kubectl get svc -n monitoring | grep prometheus
# Update in Grafana: Connections → Data sources → Prometheus → change URL
```

### Helm not found
```bash
# Ensure helm is in PATH
export PATH=$PATH:~/bin
```

---

## Cleanup

```bash
# Delete all Helm releases
helm.exe uninstall prometheus -n monitoring
helm.exe uninstall argocd -n argocd

# Delete namespaces
kubectl delete namespace production monitoring argocd

# Destroy infrastructure
cd terraform
terraform destroy
```
