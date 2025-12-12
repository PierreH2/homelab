#!/usr/bin/env bash

set -euo pipefail

### --- CONFIG --- ###
TF_DIR=$HOME/homelab/homelab/terraform
KUBECONFIG_PATH=$HOME/homelab/.kube/config

### --- CHECKS --- ###
if ! command -v terraform >/dev/null 2>&1; then
  echo "[ERREUR] Terraform n'est pas installé." >&2
  exit 1
fi

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "[ERREUR] kubeconfig introuvable : $KUBECONFIG_PATH" >&2
  exit 1
fi

echo "[INFO] Utilisation du kubeconfig : $KUBECONFIG_PATH"
export KUBE_CONFIG_PATH="$KUBECONFIG_PATH"

### --- TERRAFORM --- ###
echo "[INFO] Initialisation Terraform..."
terraform -chdir="$TF_DIR" init -upgrade

echo "[INFO] Validation du code Terraform..."
terraform -chdir="$TF_DIR" validate

echo "[INFO] Plan Terraform..."
terraform -chdir="$TF_DIR" plan -out "$TF_DIR/plan.out"

echo "[INFO] Application du plan..."
terraform -chdir="$TF_DIR" apply plan.out

echo "[OK] Namespace 'argocd' créé avec succès 🎉"