resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "8.6.0"

  # (Optional) values override
  # values = [
  #   file("argocd-values.yaml")
  # ]
}

resource "kubernetes_manifest" "guestbook" {
  manifest = yamldecode(file("/home/pierre/homelab/homelab/applications/argocd_application.yaml"))
}