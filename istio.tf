# Add the Istio Helm repository
resource "helm_release" "istio_base" {
  name       = "istio-base"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "base"
  namespace  = "istio-system"
  version    = "1.20.0"  # Pin to a stable version
  create_namespace = true

  depends_on = [
    kind_cluster.default,  # Wait for cluster to be ready
  ]
}

# Install Istiod (control plane)
resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.20.0"
  
  # Optional: Override default settings (e.g., enable auto-injection globally)
  set {
    name  = "meshConfig.enableAutoMtls"
    value = "true"
  }

  depends_on = [
    helm_release.istio_base,
  ]
}

# (Optional) Install Istio Ingress Gateway
resource "helm_release" "istio_ingress" {
  name       = "istio-ingressgateway"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-system"
  version    = "1.20.0"

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "labels.app"
    value = "istio-ingressgateway"
  }

  set {
    name  = "labels.istio"
    value = "ingressgateway"
  }

  depends_on = [
    helm_release.istiod,
  ]
}