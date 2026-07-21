# EKS Cluster Upgrade Runbook — Rolling Update (Zero Downtime)

## Strategy: EKS Managed Rolling Update (Industry Standard)

This is the approach most enterprises use. Simple, cost-effective, and zero downtime.

```
1. terraform apply → Upgrades control plane (1.30 → 1.31)
2. EKS auto-rolls  → Replaces nodes one by one (new node up → old node drained → old node terminated)
3. Done.
```

---

## How It Works (Behind the Scenes)

### Control Plane Upgrade
- AWS runs multiple API servers behind a load balancer
- Upgrades them one at a time — your pods and kubectl keep working
- Takes ~10-15 minutes
- **Zero downtime** (you may see brief API latency, but no outage)

### Node Group Rolling Update (What Happens When Pods Are Running)

```
BEFORE:
  Node A (v1.30) ──── pods: user-service-1, order-service-1
  Node B (v1.30) ──── pods: user-service-2, order-service-2
  Node C (v1.30) ──── pods: payment-service-1, payment-service-2

EKS PROCESS (automatic, one node at a time):
  1. Launch new Node D (v1.31)     → Joins cluster, becomes Ready
  2. Cordon Node A                  → No new pods scheduled on A
  3. Drain Node A                   → Evicts pods (respects PDB)
     ├── PDB check: "minAvailable met?" → Yes (replicas on other nodes)
     ├── Pods reschedule on Node D
     └── Wait for new pods to pass readiness probe
  4. Terminate Node A               → Old node gone
  5. Repeat for Node B, then Node C

AFTER:
  Node D (v1.31) ──── pods: user-service-1, order-service-1
  Node E (v1.31) ──── pods: user-service-2, order-service-2
  Node F (v1.31) ──── pods: payment-service-1, payment-service-2
```

**Zero downtime because:**
- While user-service-1 moves from Node A → Node D, user-service-2 on Node B keeps serving traffic
- PDB blocks drain if evicting would kill the last available pod
- New pod must pass readiness probe before old pod is terminated

---

## Prerequisites (Must Have for Zero Downtime)

| Requirement | Why | How |
|-------------|-----|-----|
| `replicas >= 2` | Always 1 pod alive while the other moves | Set in Helm values / deployment |
| PodDisruptionBudget | Prevents drain from killing all pods at once | `kubectl apply -f kubernetes/pdb/` |
| Readiness probe | Traffic only sent to pods that are actually ready | Defined in deployment spec |
| `max_unavailable = 1` | Only 1 node replaced at a time | Set in Terraform node group |

---

## Upgrade Steps

### Step 1: Pre-checks
```bash
# Verify current state
aws eks describe-cluster --name devops-100ms-cluster --query "cluster.version" --output text
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion

# Ensure PDBs exist
kubectl apply -f kubernetes/pdb/pdb-services.yaml
kubectl get pdb -n production

# Verify replicas >= 2
kubectl get deployments -n production
```

### Step 2: Upgrade (one command)
```bash
# Change cluster_version in variables.tf (e.g., "1.30" → "1.31")
cd terraform
terraform plan    # Review changes
terraform apply   # Execute (~30-45 min total)
```

### Step 3: Monitor
```bash
# Watch nodes rolling
kubectl get nodes -w

# Check all pods healthy
kubectl get pods -n production

# Verify versions
kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion
```

That's it. No manual drain, no scripting. EKS handles everything.

---

## Timeline

| Phase | Duration | Downtime |
|-------|----------|----------|
| Control plane upgrade | 10-15 min | None |
| Add-on updates | 2-5 min | None |
| Node rolling (3 nodes) | 15-25 min | None (with PDB + replicas ≥ 2) |
| **Total** | **~30-45 min** | **Zero** |

---

## Terraform Config (Key Settings)

```hcl
# variables.tf
variable "cluster_version" {
  default = "1.31"  # Change this to upgrade
}

# eks.tf — node group
eks_managed_node_groups = {
  main = {
    update_config = {
      max_unavailable = 1  # Only 1 node replaced at a time
    }
  }
}
```

---

## What If Something Goes Wrong?

### Control Plane Fails
- AWS auto-rolls back. No action needed.

### Node Drain Stuck (Pod Won't Evict)
```bash
# Check what's blocking
kubectl get pdb -n production
kubectl get pods -n production -o wide

# If a PDB is too strict (minAvailable = all replicas), temporarily adjust
kubectl patch pdb user-service-pdb -n production -p '{"spec":{"minAvailable":1}}'
```

### Pods Failing on New Nodes
```bash
# Check pod events
kubectl describe pod <pod-name> -n production

# Check if it's an image pull issue (new node, no cached images)
kubectl get events -n production --sort-by=.metadata.creationTimestamp | tail -20
```

---

## Interview Answer

> "We use EKS managed rolling updates. Change the cluster version in Terraform, apply it. AWS upgrades the control plane with zero downtime — it runs multiple API servers behind a load balancer and upgrades them one at a time. For nodes, EKS replaces them one by one: launches a new node, cordons and drains the old node respecting PodDisruptionBudgets, waits for pods to reschedule and pass readiness probes, then terminates the old node. As long as we have replicas >= 2 and PDBs in place, it's zero downtime. The whole process takes about 30-45 minutes."

---

## Rules to Remember

1. **One minor version at a time** — Can't jump 1.28 → 1.30, must go 1.28 → 1.29 → 1.30
2. **Control plane first, nodes second** — EKS supports n-1 skew (1.31 control plane + 1.30 nodes = fine)
3. **Add-ons update automatically** — With `most_recent = true` in Terraform
4. **No rollback for control plane** — You can only go forward (but nodes can stay on old version)
5. **Test in staging first** — Always upgrade a non-prod cluster first to catch API deprecations
