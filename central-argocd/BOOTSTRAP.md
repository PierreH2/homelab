##  Manual Bootstrap with Helm

### Step 1: Create namespace
```bash
kubectl create namespace argocd
```

### Step 2: Deploy ArgoCD with Helm
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argo-cd argo/argo-cd \
  --namespace argocd \
  --version "7.*" \
  -f argocd/values/values.yaml
```

This deploys:
- **Helm Chart**: argo-cd v7.* from argoproj.github.io
- **Values**: Configured for insecure HTTP (port 80)

### Step 3: Get admin password
```bash
kubectl port-forward service/argo-cd-argocd-server -n argocd 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Step 4: Apply central ApplicationSet
```bash
kubectl apply -f central-application.yaml
```

Once ArgoCD is healthy, the ApplicationSet will manage all your applications.

### Step 5: Fix DNS resolution (if needed)
If applications fail with DNS errors (e.g., "server misbehaving" or "dial tcp: lookup github.com"), fix CoreDNS to use public DNS servers:

```bash
# Modify CoreDNS manifest
sudo sed -i 's|forward . /etc/resolv.conf|forward . 8.8.8.8 1.1.1.1|' /var/lib/rancher/k3s/server/manifests/coredns.yaml

# Restart CoreDNS pods to apply changes
kubectl -n kube-system rollout restart deployment coredns

# Verify DNS works
kubectl run -it --rm debug-dns --image=busybox --restart=Never -- nslookup github.com
```

This resolves issues when the host's DNS (systemd-resolved) uses unreachable IPv6 servers.
