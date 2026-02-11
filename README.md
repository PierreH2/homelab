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
- [x] Generate a Let's Encrypt certificate using cert-manager for the API Gateway
- [x] Deploy a DNS server (bind)
- [x] Secure application exposure to the Internet (rate limits & Google OAuth2)
- [x] Monitor the cluster using Prometheus & Grafana
- [x] Deploy GitHub Actions runners as pods on the Kubernetes cluster
- [x] Deploy a registry (Harbor) with kyverno to enforce Harbor project usage for images
- [ ] Deploy an IDP (Keycloak → X)
- [ ] Migrate to Istio to implement a service mesh

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

### 0. Load variables
Deploy and configure a Linux OS, then deploy a Kubernetes cluster (K3S was used).

### 1. Deploy ArgoCD
ArgoCD is deployed initially via Helm.
All deployments in steps 3 and 4 are managed through ArgoCD Applications.

### 2. Deploy the Gateway, Load Balancer, and cert-manager (via ArgoCD)
Deployment includes:
- A Kubernetes Gateway (Envoy)
- DNS record purchase (OVH)
- Opening router firewall rules
- TLS certificate management for the Gateway using cert-manager and Let's Encrypt

### 3. Deploy applications (via ArgoCD)
GitOps-based deployment of all homelab applications
(Prometheus, Grafana, Apache, Plex, etc.).

---

## Applications

- **ArgoCD**: Manages GitOps workflows
- **Argo Rollouts**: Enables blue/green deployment strategies
- **Envoy Gateway**: Kubernetes API Gateway managing HTTPRoutes
- **MetalLB**: Bare-metal load balancer
- **cert-manager**: Generates and renews TLS certificates for the cluster
- **Kubernetes Dashboard**: Basic cluster state dashboard
- **Keycloak**: Identity provider (IDP) for SSO
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

