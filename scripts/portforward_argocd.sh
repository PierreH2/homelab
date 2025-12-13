#!/bin/bash
set -e

NAMESPACE="argocd"
POD=$(kubectl -n $NAMESPACE get pod -l app.kubernetes.io/name=argocd-server -o jsonpath="{.items[0].metadata.name}")

echo "🔍 Pod Argo CD trouvé : $POD"
echo "🚀 Port-forward http://localhost:8080 -> pod:8080"
kubectl -n $NAMESPACE port-forward "$POD" 8080:8080
