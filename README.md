# Homelab

This repository contains the code and materials for my homelab

# Applications

Les applications déployées :
- ArgoCD : via Terraform + helm (terraform apply)
- k8s-dashboard : via ArgoCD 
- Argo-rollouts : via helm + kustomize (kubectl kustomize . --enable-helm | kubectl apply -f -)
- Traeffik : via helm + kustomize (kubectl kustomize . --enable-helm | kubectl apply -f -)*
- Prometheus : via ArgoCD