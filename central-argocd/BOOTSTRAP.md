##  Manual Bootstrap with Kustomization

### Step 1: Deploy ArgoCD manually
```bash
kubectl apply -k argocd/
```
This deploys:
- **Namespace**: argocd
- **Helm Chart**: argo-cd v7.* from argoproj.github.io
- **Values**: Configured for insecure HTTP (port 80)

### Step 2: Create ArgoCD Secret (one-time)
Get the default admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 3: Apply central ApplicationSet
Once ArgoCD is healthy, the ApplicationSet in `central-application.yaml` will be managed by ArgoCD itself.

