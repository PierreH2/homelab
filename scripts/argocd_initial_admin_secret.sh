#!/bin/bash
set -e

NAMESPACE="argocd"
SECRET_NAME="argocd-initial-admin-secret"

echo "🔍 Récupération du mot de passe admin Argo CD..."

PASSWORD=$(kubectl -n $NAMESPACE get secret $SECRET_NAME -o jsonpath="{.data.password}" | base64 -d)

if [ -z "$PASSWORD" ]; then
  echo "❌ Impossible de récupérer le mot de passe."
  exit 1
fi

echo "🔑 Mot de passe admin : $PASSWORD"