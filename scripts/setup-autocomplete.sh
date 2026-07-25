#!/bin/bash
# =============================================================================
# Setup CLI Autocomplete — kubectl, helm, aws, terraform
# Run once: bash scripts/setup-autocomplete.sh
# Then restart terminal or run: source ~/.bashrc
# =============================================================================

echo "Setting up CLI autocomplete..."

# --- kubectl autocomplete + alias 'k' ---
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# --- helm autocomplete ---
echo 'source <(helm.exe completion bash)' >> ~/.bashrc

# --- aws CLI autocomplete ---
echo 'complete -C aws_completer aws' >> ~/.bashrc

# --- terraform autocomplete ---
terraform -install-autocomplete 2>/dev/null || echo 'terraform autocomplete already installed'

# --- Apply now ---
source ~/.bashrc

echo ""
echo "=== Autocomplete Installed ==="
echo ""
echo "Usage (press Tab to complete):"
echo "  kubectl get p<TAB>          → pods, pv, pvc"
echo "  kubectl get pods -n <TAB>   → lists all namespaces"
echo "  kubectl describe pod u<TAB> → completes pod name"
echo "  k get pods -n prod<TAB>     → production"
echo "  helm.exe list -n <TAB>      → lists namespaces"
echo "  aws ec2 describe-<TAB>      → shows all describe-* commands"
echo ""
echo "Restart terminal or run: source ~/.bashrc"
