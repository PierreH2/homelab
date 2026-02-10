# Argo CD (Helm)

## Files
- namespace.yaml: namespace creation.
- values.yaml: Helm values (HTTP on port 80).
- httproute.yaml: Gateway route to the Argo CD server.

## Process de déploiement initial

1) Installer Argo CD via Helm
- `helm repo add argo https://argoproj.github.io/argo-helm`
- `helm repo update`
- `helm install argo-cd argo/argo-cd \
  -n argocd --create-namespace \
  -f namespaces-apps/argocd/values.yaml \
  --version 8.6.0`

2) Appliquer la route Gateway
- `kubectl apply -f namespaces-apps/argocd/httproute.yaml`

3) Verifier l acces HTTP via le Gateway
- Le service expose le port 80 et `configs.params.server.insecure=true`.
- Le HTTPRoute cible deja `argo-cd-argocd-server:80`.
