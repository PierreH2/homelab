kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls piron-homelab-ca \
  --cert=piron-homelab-ca.crt \
  --key=piron-homelab-ca.key \
  -n cert-manager
