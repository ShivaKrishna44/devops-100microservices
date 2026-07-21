# Production Issues - Troubleshooting Lab

This guide contains real-world production scenarios you can simulate and practice troubleshooting.

---

## Issue 1: Pod CrashLoopBackOff

**Symptom:** Pods keep restarting, `kubectl get pods` shows CrashLoopBackOff

**How to Simulate:**
```bash
# Set invalid image tag
kubectl set image deployment/user-service user-service=invalid-image:v999 -n production
```

**Troubleshooting Steps:**
```bash
# 1. Check pod status
kubectl get pods -n production -l app=user-service

# 2. Describe the pod for events
kubectl describe pod -n production -l app=user-service

# 3. Check logs (previous container if crashing)
kubectl logs -n production -l app=user-service --previous

# 4. Check events
kubectl get events -n production --sort-by=.metadata.creationTimestamp | tail -20
```

**Fix:**
```bash
# Rollback deployment
kubectl rollout undo deployment/user-service -n production
kubectl rollout status deployment/user-service -n production
```

---

## Issue 2: OOMKilled (Out of Memory)

**Symptom:** Pod terminated with OOMKilled reason

**How to Simulate:**
Edit `charts/microservice/values-order-service.yaml`:
```yaml
resources:
  limits:
    memory: 64Mi  # Too low for the app
```

**Troubleshooting Steps:**
```bash
# 1. Check pod termination reason
kubectl get pods -n production -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}'

# 2. Check resource usage
kubectl top pods -n production

# 3. Describe pod for OOMKilled event
kubectl describe pod <pod-name> -n production | grep -A5 "Last State"

# 4. Check Prometheus alert
# Query: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}
```

**Fix:**
```bash
# Increase memory limit in values file and sync via ArgoCD
# Or patch directly:
kubectl patch deployment order-service -n production --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"512Mi"}]'
```

---

## Issue 3: High Latency / Timeout Cascade

**Symptom:** Order service responds slowly, timeouts propagate to clients

**How to Simulate:**
```bash
# Enable latency simulation in payment service
kubectl set env deployment/payment-service SIMULATE_LATENCY=true -n production
```

**Troubleshooting Steps:**
```bash
# 1. Check response times via Prometheus
# Query: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{job="order-service"}[5m]))

# 2. Check if payment service is slow
kubectl exec -n production deploy/order-service -- curl -w "%{time_total}s" http://payment-service:5000/health

# 3. Check HPA scaling
kubectl get hpa -n production

# 4. Look at Grafana dashboard for latency spikes
```

**Fix:**
```bash
# Disable latency simulation
kubectl set env deployment/payment-service SIMULATE_LATENCY=false -n production

# Long-term: implement circuit breaker, increase timeouts, add retries
```

---

## Issue 4: 5xx Error Rate Spike

**Symptom:** Increased 500 errors from payment service

**How to Simulate:**
```bash
# Set 30% failure rate
kubectl set env deployment/payment-service FAILURE_RATE=0.3 -n production
```

**Troubleshooting Steps:**
```bash
# 1. Check error rate in Prometheus
# Query: rate(http_requests_total{status=~"5..",job="payment-service"}[5m])

# 2. Check application logs
kubectl logs -n production -l app=payment-service --tail=50 | grep ERROR

# 3. Check if it's scaling related
kubectl get pods -n production -l app=payment-service -o wide

# 4. Check resource pressure
kubectl top pods -n production -l app=payment-service
```

**Fix:**
```bash
kubectl set env deployment/payment-service FAILURE_RATE=0.0 -n production
```

---

## Issue 5: ArgoCD Sync Failed

**Symptom:** Application shows "OutOfSync" or "SyncFailed" in ArgoCD

**How to Simulate:**
```bash
# Introduce a bad Helm template
# Add invalid YAML to a template file and push to Git
```

**Troubleshooting Steps:**
```bash
# 1. Check ArgoCD app status
argocd app get user-service

# 2. Check sync history
argocd app history user-service

# 3. Check the diff
argocd app diff user-service

# 4. Check ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

**Fix:**
```bash
# Fix the template and push, or manual sync with --force
argocd app sync user-service --force

# Or rollback
argocd app rollback user-service
```

---

## Issue 6: Node Not Ready

**Symptom:** kubectl shows nodes in NotReady state, pods pending

**Troubleshooting Steps:**
```bash
# 1. Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# 2. Check for resource pressure
kubectl describe node <node-name> | grep -A5 "Conditions"

# 3. Check kubelet status (if SSH access available)
systemctl status kubelet
journalctl -u kubelet --since "10 minutes ago"

# 4. Check for disk pressure
kubectl describe node <node-name> | grep "DiskPressure\|MemoryPressure"

# 5. Check AWS console for instance health
aws ec2 describe-instance-status --instance-ids <instance-id>
```

---

## Issue 7: DNS Resolution Failure

**Symptom:** Services can't find each other, connection refused errors

**Troubleshooting Steps:**
```bash
# 1. Check CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. Test DNS from a pod
kubectl run dns-test --rm -it --image=busybox -- nslookup payment-service.production.svc.cluster.local

# 3. Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# 4. Check service exists
kubectl get svc -n production

# 5. Check endpoints
kubectl get endpoints payment-service -n production
```

---

## Issue 8: ImagePullBackOff

**Symptom:** Pod stuck in ImagePullBackOff

**How to Simulate:**
```bash
# Reference non-existent image
kubectl set image deployment/user-service user-service=589389425618.dkr.ecr.us-east-1.amazonaws.com/user-service:nonexistent -n production
```

**Troubleshooting Steps:**
```bash
# 1. Describe pod for pull error
kubectl describe pod -n production -l app=user-service | grep -A3 "Events"

# 2. Check if ECR auth is valid
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 589389425618.dkr.ecr.us-east-1.amazonaws.com

# 3. Check if image exists
aws ecr describe-images --repository-name user-service --image-ids imageTag=latest

# 4. Check pull secrets
kubectl get secrets -n production | grep docker
```

---

## Issue 9: Horizontal Pod Autoscaler Not Scaling

**Symptom:** HPA shows <unknown> for metrics, not scaling up under load

**Troubleshooting Steps:**
```bash
# 1. Check HPA status
kubectl get hpa -n production
kubectl describe hpa user-service -n production

# 2. Check if metrics-server is running
kubectl get pods -n kube-system -l k8s-app=metrics-server
kubectl top pods -n production

# 3. Check resource requests are set (required for HPA)
kubectl get deployment user-service -n production -o jsonpath='{.spec.template.spec.containers[0].resources}'

# 4. Generate load to test scaling
kubectl run load-gen --rm -it --image=busybox -- sh -c "while true; do wget -q -O- http://user-service.production:5000/api/users; done"
```

---

## Issue 10: Persistent Volume Stuck in Pending

**Symptom:** PVC stuck in Pending, pods can't start

**Troubleshooting Steps:**
```bash
# 1. Check PVC status
kubectl get pvc -n monitoring

# 2. Describe PVC for events
kubectl describe pvc <pvc-name> -n monitoring

# 3. Check storage class exists
kubectl get storageclass

# 4. Check EBS CSI driver
kubectl get pods -n kube-system -l app=ebs-csi-controller

# 5. Check IRSA role for EBS CSI
kubectl describe sa ebs-csi-controller-sa -n kube-system | grep Annotations
```

---

## Monitoring Queries (Prometheus/Grafana)

### Key PromQL Queries

```promql
# Request rate per service
rate(http_requests_total[5m])

# Error rate percentage
100 * rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Pod restart count
increase(kube_pod_container_status_restarts_total[1h])

# Memory usage vs limit
container_memory_usage_bytes / container_spec_memory_limit_bytes * 100

# CPU throttling
rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m]) * 100

# Payment failures
rate(payment_call_failures_total[5m])
```

---

## Quick Reference Commands

```bash
# Check overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# Check ArgoCD apps
argocd app list

# Port-forward Grafana locally
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# Port-forward ArgoCD locally
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Quick pod resource check
kubectl top pods -n production --sort-by=memory
kubectl top pods -n production --sort-by=cpu
```
