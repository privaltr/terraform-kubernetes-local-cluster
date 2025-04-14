# Kasten K10 Namespace Creation
resource "kubectl_manifest" "k10_namespace" {
  count     = var.enable_k10 ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.k10_namespace}
YAML
  depends_on = [
    kind_cluster.default
  ]
}

# Kasten K10 TLS Module (for secure communication)
module "k10_tls" {
  count     = var.enable_k10 ? 1 : 0
  source    = "./modules/tls-cert"
  namespace = var.k10_namespace
  dns_names = [
    "k10.${var.base_domain}"
  ]
  certs_path = var.certs_path

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
  ]
}

# Kasten K10 Helm Release Deployment
resource "helm_release" "kasten_k10_deployment" {
  count            = var.enable_k10 ? 1 : 0
  name             = "k10"
  repository       = "https://charts.kasten.io"
  chart            = "k10"
  version          = "7.5.8"  # Use the latest stable version
  namespace        = var.k10_namespace
  create_namespace = true
  timeout          = 420  # Increased timeout to 20 minutes (1200 seconds)


  # Add storage configuration
  set {
    name  = "global.persistence.storageClass"
    value = "standard"
  }

  set {
    name  = "global.persistence.size"
    value = "50Gi"
  }

  depends_on = [
    kind_cluster.default,
    kubectl_manifest.k10_namespace,
    module.k10_tls,
  ]
}

# Kasten K10 Ingress using ProjectContour HTTPProxy
resource "kubectl_manifest" "k10_ingress" {
  count     = var.enable_k10 ? 1 : 0
  yaml_body = <<YAML
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  annotations:
    kubernetes.io/ingress.class: contour
  name: kasten-ingress
  namespace: ${var.k10_namespace}
spec:
  virtualhost:
    fqdn: k10.${var.base_domain}
    tls:
      secretName: ${module.k10_tls[0].cert_secret}
  routes:
    - conditions:
        - prefix: /
      enableWebsockets: true  # Critical for Kasten
      services:
        - name: gateway       # Correct service name
          port: 80           # Matches service definition
      pathRewritePolicy:
        replacePrefix:
        - replacement: /k10/
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.kasten_k10_deployment,
    module.k10_tls,
  ]
}
