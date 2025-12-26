# Homelab

Collection de manifests, charts et scripts pour déployer et gérer mon homelab Kubernetes (k3s / clusters locaux).

## But
Organiser les applications (Argo Rollouts, cert-manager, Grafana, Prometheus, Traefik, MetalLB, etc.), l'infrastructure Terraform et les scripts d'automatisation pour déploiement reproductible.

## Arborescence principale
- namespaces-apps/ — kustomize / apps par namespace (charts embarqués pour reproducibilité)
- scripts/ — utilitaires (deploy, terraform, certificates, port-forward)
- terraform/ — infra déclarative (argocd, clusters, ressources cloud éventuelles)
- .env — variables d'environnement locales

## Prérequis
- bash, kubectl, kustomize, helm, terraform installés
- accès au cluster (KUBECONFIG)
- variables locales dans `.env` (ne pas committer de secrets)

## Déploiement rapide
1. Charger variables :
```bash
source .env
```
2. Déployer terraform (si utilisé) :
```bash
cd terraform && ./terraform_deploy.sh
```
3. Appliquer manifests / kustomize :
```bash
./scripts/kubectl_deploy.sh
```
4. Initialiser ArgoCD (si nécessaire) :
```bash
./scripts/argocd_initial_admin_secret.sh
./scripts/portforward_argocd.sh
```

## Gestion des certificats
- scripts/certificate contient generation et import pour k3s.
- cert-manager manifests dans namespaces-apps/cert-manager.

## Ajouter / modifier une application
- Créer un répertoire sous `namespaces-apps/<app>` avec `kustomization.yaml` et ressources.
- Si c'est un chart, placer une copie dans `charts/` pour versionning local.
- Commit + push ; ArgoCD (si présent) s'occupe de la synchronisation.

## Scripts utiles
- scripts/kubectl_deploy.sh — applique tous les kustomize
- scripts/terraform_deploy.sh — wrapper terraform
- scripts/argocd_initial_admin_secret.sh — init ArgoCD secret
- scripts/portforward_argocd.sh — port-forward local

## Sécurité / bonnes pratiques
- Ne pas committer secrets : utiliser SealedSecrets / SOPS ou ArgoCD Vault Plugin.
- Verrouiller les valeurs sensibles dans `.env` ou gestionnaire de secrets.

## Contribuer
- Ouvrir une PR décrivant la modification, tests locaux obligatoires (kubectl apply --dry-run si possible).
- Respecter les kustomize/Helm existants et versions embarquées.

## Licence
Voir fichier LICENSE à la racine.

# Applications

Les applications déployées :
- ArgoCD : via Terraform + helm (terraform apply)
- k8s-dashboard : via ArgoCD 
- Argo-rollouts : via helm + kustomize (kubectl kustomize . --enable-helm | kubectl apply -f -)
- Traeffik : via helm + kustomize (kubectl kustomize . --enable-helm | kubectl apply -f -)*
- Prometheus : via ArgoCD