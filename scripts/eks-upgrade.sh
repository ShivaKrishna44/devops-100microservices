#!/bin/bash
# =============================================================================
# EKS Blue-Green Upgrade (Simple 3-Step)
#
# Strategy:
#   Step 1: terraform apply  → upgrades control plane + creates NEW node group
#   Step 2: drain old nodes  → pods move to new nodes
#   Step 3: terraform apply  → removes OLD node group
#
# Zero downtime as long as replicas >= 2
# =============================================================================

set -e
CLUSTER_NAME="devops-100ms-cluster"
REGION="us-east-1"

echo "============================================"
echo "  EKS Blue-Green Upgrade"
echo "============================================"

case "${1}" in

  # ─────────────────────────────────────────────────────────
  # STEP 1: Upgrade control plane + create new node group
  # ─────────────────────────────────────────────────────────
  step1)
    echo ""
    echo ">>> Step 1: Upgrade control plane + create GREEN node group"
    echo "    - Update cluster_version in variables.tf (1.30 → 1.31)"
    echo "    - Keep BOTH blue and green node groups in eks.tf"
    echo ""
    echo "Then run:"
    echo "    cd terraform"
    echo "    terraform plan"
    echo "    terraform apply"
    echo ""
    echo "Wait for:"
    echo "    - Control plane: ~10-15 min"
    echo "    - New node group: ~5 min"
    echo ""
    echo "Verify:"
    echo "    kubectl get nodes"
    echo "    # You should see BOTH old (1.30) and new (1.31) nodes"
    ;;

  # ─────────────────────────────────────────────────────────
  # STEP 2: Drain old nodes (pods migrate to new nodes)
  # ─────────────────────────────────────────────────────────
  step2)
    echo ""
    echo ">>> Step 2: Drain old (blue) nodes"
    echo ""

    # Find old nodes by label
    OLD_NODES=$(kubectl get nodes -l node-group=blue -o jsonpath='{.items[*].metadata.name}')

    if [ -z "$OLD_NODES" ]; then
      echo "No blue nodes found. Trying to find nodes by version..."
      # Alternatively find by kubelet version if labels aren't set
      OLD_NODES=$(kubectl get nodes -o jsonpath='{range .items[?(@.status.nodeInfo.kubeletVersion=="v1.30.*")]}{.metadata.name}{" "}{end}')
    fi

    if [ -z "$OLD_NODES" ]; then
      echo "ERROR: No old nodes found to drain!"
      exit 1
    fi

    echo "Old nodes to drain: $OLD_NODES"
    echo ""

    for NODE in $OLD_NODES; do
      echo "--- Cordoning $NODE (no new pods) ---"
      kubectl cordon "$NODE"

      echo "--- Draining $NODE (pods will move to new nodes) ---"
      kubectl drain "$NODE" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --grace-period=60 \
        --timeout=120s

      echo "--- $NODE drained successfully ---"
      echo ""
    done

    echo "All old nodes drained. Pods are now on green nodes."
    echo ""
    echo "Verify:"
    echo "    kubectl get pods -n production -o wide"
    echo "    kubectl get nodes"
    ;;

  # ─────────────────────────────────────────────────────────
  # STEP 3: Delete old node group
  # ─────────────────────────────────────────────────────────
  step3)
    echo ""
    echo ">>> Step 3: Remove old (blue) node group"
    echo ""
    echo "    - In eks.tf: remove/comment-out the 'blue' node group block"
    echo "    - Run:"
    echo "        cd terraform"
    echo "        terraform plan    # Should show: destroy blue node group"
    echo "        terraform apply"
    echo ""
    echo "    This terminates the old EC2 instances."
    echo "    Done! Cluster fully upgraded."
    ;;

  # ─────────────────────────────────────────────────────────
  # STATUS: Check current state
  # ─────────────────────────────────────────────────────────
  status)
    echo ""
    echo "--- Cluster Version ---"
    aws eks describe-cluster --name $CLUSTER_NAME --region $REGION \
      --query "cluster.version" --output text

    echo ""
    echo "--- Node Versions ---"
    kubectl get nodes -o custom-columns=\
NAME:.metadata.name,\
VERSION:.status.nodeInfo.kubeletVersion,\
GROUP:.metadata.labels.node-group,\
STATUS:.status.conditions[-1].type

    echo ""
    echo "--- Pods Distribution ---"
    kubectl get pods -n production -o wide --no-headers | awk '{print $7}' | sort | uniq -c
    ;;

  *)
    echo "Usage: $0 {step1|step2|step3|status}"
    echo ""
    echo "  step1  - Instructions to create new node group"
    echo "  step2  - Drain old nodes (run after step1 is complete)"
    echo "  step3  - Instructions to delete old node group"
    echo "  status - Show current cluster/node state"
    ;;
esac
