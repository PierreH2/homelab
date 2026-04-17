# Homelab

This repository is a collection of manifests, charts, and scripts used to deploy
and manage my Kubernetes homelab (K3S running on Arch Linux).

## Architecture
The homelab is based on a single-node Kubernetes cluster (K3S) running on Arch Linux.
Applications are deployed using GitOps via ArgoCD and exposed to the Internet through
a Kubernetes API Gateway (Envoy), secured with TLS and OAuth2 authentication.

Persistent data is stored on a NAS mounted as a Samba subvolume on the host machine.

---

## TO DO

- [x] Install Arch Linux
- [x] Install K3S
- [x] Deploy a NAS for storage
- [x] Deploy ArgoCD using Helm
- [x] Deploy applications using GitOps
- [x] Deploy a Kubernetes API Gateway (Traefik → Envoy)
- [x] Secure a DNS hostname (piron-tech.com at OVH)
- [x] Generate a Let's Encrypt certificate using cert-manager for the API Gateway
- [x] Deploy a DNS server (bind)
- [x] Secure application exposure to the Internet (rate limits & Google OAuth2)
- [x] Monitor the cluster using Prometheus & Grafana
- [x] Deploy GitHub Actions runners as pods on the Kubernetes cluster
- [x] Deploy a registry (Harbor) with kyverno to enforce Harbor project usage for images (registry.piron-tech.com/proxy/[IMAGE_NAME]:[TAG])
- [X] Deploy an IDP (Keycloak → Authentik)
- [ ] Deploy Tempo & Loki for distributed tracing and log aggregation
- [ ] Migrate to Istio to implement a service mesh
- [ ] Deploy a secret manager instead of using Kubernetes secrets (Vault)

---

## Repository Structure

- `namespaces-apps/` — Application manifests (YAML)
- `scripts/` — Utility scripts (deploy, certificates, port-forwarding)

---

## Prerequisites

- A Linux machine with the following tools installed:
  - Kubernetes
  - Helm
  - kubectl

---

## Quick Deployment Guide

### Step 1 — Run the setup script
Configure the OS and deploy K3S by running the setup script:

```bash
bash scripts/setup/setup-fedora-homelab.sh
```

This script:
- Disables the GUI
- Installs required packages (kubectl, Helm, Docker, etc.)
- Creates the required directory structure
- Deploys K3S

### Step 2 — Bootstrap ArgoCD
Deploy ArgoCD manually using Kustomize:

```bash
kubectl apply -k central-argocd/argocd/
```

Wait for ArgoCD to become healthy, then retrieve the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

See `central-argocd/BOOTSTRAP.md` for more details.

### Step 3 — Deploy the central ApplicationSet (App-of-Apps)
Apply the central ApplicationSet that manages the entire stack via the App-of-Apps pattern:

```bash
kubectl apply -f central-argocd/central-application.yaml
```

This ApplicationSet deploys all applications in dependency order (using sync waves):
- **Wave 0–1**: Infrastructure (MetalLB, Envoy Gateway)
- **Wave 2–3**: Registry & policy (Harbor, Kyverno, cert-manager)
- **Wave 4**: GitOps & rollouts (ArgoCD config, Argo Rollouts)
- **Wave 9**: Auth & CI (Authentik, GitHub Runners)
- **Wave 10+**: Observability & applications (Grafana, Prometheus, OAuth2 Proxy, Dashboard, Plex, etc.)

ArgoCD will continuously reconcile all apps from this repository.

---

## Applications

- **ArgoCD**: Manages GitOps workflows
- **Argo Rollouts**: Enables blue/green deployment strategies
- **Envoy Gateway**: Kubernetes API Gateway managing HTTPRoutes
- **MetalLB**: Bare-metal load balancer
- **cert-manager**: Generates and renews TLS certificates for the cluster
- **Kubernetes Dashboard**: Basic cluster state dashboard
- **Authentik**: Identity provider (IDP) for SSO (for Grafana and argocd)
- **Harbor**: Private registry for container images
- **Kyverno**: Policy engine to enforce Harbor usage and verify image signatures
- **Prometheus**: Time-series database for Kubernetes and node metrics,
  secured with Google OAuth2 for Internet exposure
- **Grafana**: Advanced dashboards for cluster state and historical metrics
- **Apache**: HTTP server
- **Plex**: Media server for video and image storage

---

## Findings & Lessons Learned

### Traefik Gateway
The Traefik Kubernetes Gateway does not support the `BackendTLSPolicies` CRD,
which prevents TLS connections from the Gateway to backend pods.
Traefik only supports TLS termination at the frontend.

### DNS
The Bouygues BBox router does not allow modification of the primary DNS server
for security reasons.
As a result, the DNS server (Bind) must be manually configured as the primary DNS
on each machine by editing:
- `/etc/hosts` on Linux
- `C:\Windows\System32\drivers\etc\hosts` on Windows

### Bitnami discontinued Keycloak
The keycloak official helm charts points to bitnami/... but it is now bitnamilegacy/... that contains the images. Fix must be made manually on the values.yaml

### ASUS Fan Control (asusctl)
ASUS ROG laptops require `asusctl` to control fan curves on Linux. Without it, fans may not respond to thermal load.

**`asusctl` is not supported on Ubuntu.** The tool relies on kernel modules and DKMS packages that are only available for Arch Linux and Fedora. On Ubuntu, these packages are absent and the kernel module cannot be compiled, making fan curve control unavailable. 

### K3s Stop Leaves Zombie Pods
`systemctl stop k3s` does not terminate containerd processes and leaves them in a "zombie" state. Use `k3s-killall.sh` to fully cleanup pods after k3s system stopped.

