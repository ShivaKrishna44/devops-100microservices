# Production Issues Lab — Hands-On Results

All issues simulated and fixed on live EKS cluster (devops-100ms-cluster, v1.31, 3 nodes).

---

## Issue 1: ImagePullBackOff (Wrong Image Tag)

**Break:**
```bash
kubectl set image deployment/user-service nginx=nginx:nonexistent-tag -n production
```

**Symptom:**
```
$ kubectl get pods -n production -l app=user-service
NAME                            READY   STATUS             RESTARTS   AGE
user-service-668c98579c-7xxv4   1/1     Running            0          3h13m   ← OLD (still serving)
user-service-8656ff47c6-kn8pz   0/1     ImagePullBackOff   0          4m13s   ← NEW (broken)
```

**Diagnosis:**
```
$ kubectl describe pod user-service-8656ff47c6-kn8pz -n production
Events:
  Warning  Failed   2m  kubelet  Failed to pull image "nginx:nonexistent-tag"
  Normal   BackOff  29s (x351 over 80m)  kubelet  Back-off pulling image "nginx:nonexistent-tag"
```

**Key observation:** Old pods stay Running — Kubernetes rolling update won't kill healthy pods until new ones are Ready. Users NOT affected.

**Fix:**
```bash
kubectl set image deployment/user-service nginx=nginx:alpine -n production
# Or rollback:
kubectl rollout undo deployment/user-service -n production
```

**Interview takeaway:** "In a rolling update, Kubernetes protects availability by keeping old pods alive while new pods are failing. Check `kubectl describe pod` → Events for the exact pull error."

---

## Issue 2: CrashLoopBackOff (Container Exits Immediately)

**Break:**
```bash
kubectl set image deployment/order-service nginx=busybox:latest -n production
```

**Symptom:**
```
$ kubectl get pods -n production -l app=order-service
order-service-758bfbd94b-8dvt8   1/1     Running            0          106m   ← OLD (still serving)
order-service-8556fd5996-269nr   0/1     CrashLoopBackOff   2 (19s)    36s    ← NEW (crashing)
```

**Diagnosis:**
```bash
$ kubectl logs -n production order-service-8556fd5996-269nr
# EMPTY — no output at all!

$ kubectl logs -n production order-service-8556fd5996-269nr --previous
# EMPTY — container exits before writing anything
```

**Why empty logs?** Busybox starts a shell, finds no input (non-interactive), exits with code 0. No stdout = no logs.

**Key insight:** When logs are empty, check the exit code:
- Exit code 0 = process finished normally (wrong image/entrypoint, no long-running process)
- Exit code 1 = application error
- Exit code 137 = OOMKilled
- Exit code 139 = Segfault

**Fix:**
```bash
kubectl rollout undo deployment/order-service -n production
```

**Interview takeaway:** "Empty logs in CrashLoopBackOff means the container exits before producing output. I check `kubectl describe pod` for the exit code — that tells me the direction even without logs."

---

## Issue 3: OOMKilled (Memory Limit Too Low)

**Break:**
```bash
kubectl set resources deployment/payment-service -n production --requests=memory=2Mi --limits=memory=2Mi
```

**Symptom:**
```
$ kubectl describe pod -n production -l app=payment-service
Events:
  Warning  FailedCreatePodSandBox  kubelet  Failed to create pod sandbox:
  OCI runtime create failed: runc create failed: unable to start container process:
  container init was OOM-killed (memory limit too low?)
```

**Diagnosis:**
- Exit code 137 = OOMKilled
- 2Mi is too low for any container (even nginx needs ~5-10Mi minimum)
- Container killed by kernel before it even starts

**Fix:**
```bash
kubectl set resources deployment/payment-service -n production --requests=memory=64Mi --limits=memory=256Mi
```

**Interview takeaway:** "Exit code 137 = OOMKilled. Fix is to increase memory limit. To prevent: use `kubectl top pods` to see actual usage, set limits with 20-30% buffer above normal. Add Prometheus alert for memory > 90% of limit."

---

## Issue 4: Pod Stuck in Pending (Insufficient Resources)

**Break:**
```bash
kubectl set resources deployment/notification-service -n production --requests=cpu=8
```

**Symptom:**
```
$ kubectl get pods -n production -l app=notification-service
notification-service-xxx   0/1   Pending   0   30s
```

**Diagnosis:**
```
$ kubectl describe pod -n production -l app=notification-service
Events:
  Warning  FailedScheduling  default-scheduler
  0/3 nodes are available: 3 Insufficient cpu.
```

**Why?** Requested 8 CPUs but t3.medium only has 2 vCPUs. No node can fit this pod.

**Fix:**
```bash
kubectl set resources deployment/notification-service -n production --requests=cpu=50m
```

**Interview takeaway:** "Pending means the scheduler can't find a node that matches. Always check `kubectl describe pod` → Events. Common causes: insufficient CPU/memory, node selector mismatch, PVC can't bind in the same AZ."

---

## Issue 5: Liveness Probe Failure (Pod Keeps Restarting)

**Break:**
```bash
kubectl patch deployment payment-service -n production --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/livenessProbe","value":{"httpGet":{"path":"/","port":8888},"initialDelaySeconds":5,"periodSeconds":5,"failureThreshold":2}}
]'
```

**Symptom:**
```
$ kubectl get pods -n production -l app=payment-service -w
payment-service-59f68b6bb9-9kmcb   1/1     Running            2 (6s ago)   27s
payment-service-59f68b6bb9-xpsgq   1/1     Running            2 (5s ago)   26s
payment-service-59f68b6bb9-9kmcb   0/1     CrashLoopBackOff   3 (0s ago)   41s
payment-service-59f68b6bb9-xpsgq   0/1     CrashLoopBackOff   3 (1s ago)   42s
```

**Diagnosis:**
```
$ kubectl get events -n production
Warning   Unhealthy   pod/payment-service-59f68b6bb9-9kmcb
  Liveness probe failed: Get "http://10.0.19.27:8888/": dial tcp 10.0.19.27:8888: connect: connection refused

Normal    Killing     pod/payment-service-59f68b6bb9-9kmcb
  Container nginx failed liveness probe, will be restarted
```

**Root cause:** Liveness probe checks port 8888, but nginx listens on port 80. Connection refused → Kubernetes thinks app is dead → restarts it → same failure → CrashLoopBackOff.

**Fix:**
```bash
kubectl patch deployment payment-service -n production --type=json -p='[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'
```

**Interview takeaway:** "Liveness probe failure with connection refused means probe is checking wrong port or path. I check `kubectl describe pod` → Liveness section for configured port/path → compare with what the container actually exposes."

---

## Issue 6: Node Drain (Simulate Maintenance/Upgrade)

**Break:**
```bash
kubectl drain ip-10-0-24-181.ec2.internal --ignore-daemonsets --delete-emptydir-data
```

**What happened:**
```
evicting pod production/user-service-67865c46dd-qr85w
evicting pod argocd/argocd-application-controller-0
evicting pod monitoring/prometheus-grafana-6558c4b74-fls26
evicting pod kube-system/coredns-79767d7cc-2vvk9
pod/user-service-67865c46dd-qr85w evicted
pod/argocd-application-controller-0 evicted
node/ip-10-0-24-181.ec2.internal drained
```

**After drain — pods rescheduled to other nodes:**
```
$ kubectl get pods -n production -o wide
notification-service-58c744d856-2f7qf   1/1   Running   ip-10-0-45-93.ec2.internal
notification-service-58c744d856-g8hqk   1/1   Running   ip-10-0-4-193.ec2.internal
order-service-77fb87b5bf-h5k67          1/1   Running   ip-10-0-4-193.ec2.internal
order-service-77fb87b5bf-t6tg8          1/1   Running   ip-10-0-45-93.ec2.internal
payment-service-b8bc56bc9-6xlk2         1/1   Running   ip-10-0-45-93.ec2.internal
payment-service-b8bc56bc9-92ssn         1/1   Running   ip-10-0-4-193.ec2.internal
user-service-67865c46dd-7skt2           1/1   Running   ip-10-0-4-193.ec2.internal
user-service-67865c46dd-bhx8d           1/1   Running   ip-10-0-45-93.ec2.internal
```

**Node status after drain:**
```
$ kubectl get nodes
ip-10-0-24-181.ec2.internal   Ready,SchedulingDisabled   <none>   3h24m   v1.31.14-eks-bca9cf6
ip-10-0-4-193.ec2.internal    Ready                      <none>   3h24m   v1.31.14-eks-bca9cf6
ip-10-0-45-93.ec2.internal    Ready                      <none>   3h24m   v1.31.14-eks-bca9cf6
```

**Key observations:**
- `SchedulingDisabled` = node is cordoned, no new pods scheduled
- All production pods redistributed to remaining 2 nodes
- DaemonSets (aws-node, kube-proxy, node-exporter) stayed — `--ignore-daemonsets` skips them
- Zero downtime — user-service-7skt2 kept serving while qr85w moved

**Fix (bring node back):**
```bash
kubectl uncordon ip-10-0-24-181.ec2.internal
```

**Interview takeaway:** "Drain is what happens during EKS rolling upgrades — automated cordon + evict + reschedule. With replicas ≥ 2, traffic continues flowing to the surviving pod while the other reschedules. This is why PDBs and multiple replicas matter."

---

## Summary: Troubleshooting Pattern

For ANY Kubernetes issue, follow this flow:

```
1. kubectl get pods            → What's the STATUS?
2. kubectl describe pod <name> → What do EVENTS say?
3. kubectl logs <name>         → What did the app print?
4. kubectl logs --previous     → What did it print before crashing?
5. kubectl get events          → What's happening cluster-wide?
```

| Status | Likely Cause | First Command |
|--------|-------------|---------------|
| ImagePullBackOff | Wrong image/tag, ECR auth | `describe pod` → Events |
| CrashLoopBackOff | App crash, wrong entrypoint, OOM | `logs --previous`, check exit code |
| Pending | No resources, node selector, PVC | `describe pod` → Events |
| CreateContainerConfigError | Missing secret/configmap | `describe pod` → Events |
| Running but slow | Wrong resource limits, downstream dependency | `top pods`, check dependent services |

## Exit Code Cheat Sheet

| Code | Meaning | Fix |
|------|---------|-----|
| 0 | Process finished normally | Wrong image (no long-running process) |
| 1 | Application error | Check logs, fix code/config |
| 127 | Command not found | Wrong entrypoint in Dockerfile |
| 137 | OOMKilled (SIGKILL) | Increase memory limit |
| 139 | Segfault | Application bug |
| 143 | SIGTERM (graceful stop) | Normal termination (not an error) |


---

## Issue 7: Missing Secret — CreateContainerConfigError

**Break:**
```bash
kubectl patch deployment order-service -n production --type=json -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/env","value":[{"name":"DB_PASSWORD","valueFrom":{"secretKeyRef":{"name":"db-credentials","key":"password"}}}]}
]'
```

**Symptom:**
```
$ kubectl get pods -n production -l app=order-service
order-service-75f66699dd-mxhf5   0/1     CreateContainerConfigError   0     48s    ← NEW (broken)
order-service-77fb87b5bf-h5k67   1/1     Running                      0     3h51m  ← OLD (still serving)
order-service-77fb87b5bf-t6tg8   1/1     Running                      0     3h51m  ← OLD (still serving)
```

**Diagnosis:**
```
$ kubectl describe pod order-service-75f66699dd-mxhf5 -n production
Events:
  Warning  Failed  6m34s (x12 over 8m42s)  kubelet  Error: secret "db-credentials" not found
```

**Key observation:** Old pods stay Running — users NOT affected. The new pod can't start because it references a secret that doesn't exist.

**Fix — Create the missing secret:**
```bash
$ kubectl create secret generic db-credentials --from-literal=password=mypassword123 -n production
secret/db-credentials created
```

**Self-healing result (no restart needed):**
```
$ kubectl get events -n production | findstr "order"
Normal  ScalingReplicaSet   deployment/order-service   Scaled up replica set order-service-75f66699dd to 2 from 1
Normal  ScalingReplicaSet   deployment/order-service   Scaled down replica set order-service-77fb87b5bf to 0 from 1
```

Pod automatically started once secret was created → rolling update completed → old pods terminated.

```
$ kubectl get pods -n production -l app=order-service
order-service-75f66699dd-mxhf5   1/1     Running   0   13m
order-service-75f66699dd-nc9gh   1/1     Running   0   20s
```

**Interview takeaway:** "CreateContainerConfigError means the pod references a secret or configmap that doesn't exist. Once I create it, the pod starts automatically — no need to delete/restart the pod. In production, this usually happens when someone deploys code that expects a new secret before the secret is created. Fix: ensure secrets are created before deploying the new version (or use external-secrets-operator for automated sync from Vault/Secrets Manager)."
