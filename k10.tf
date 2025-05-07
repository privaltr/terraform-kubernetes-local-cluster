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

# Kasten K10 Helm Release Deployment
resource "helm_release" "k10_deployment" {
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

  # Configure snapshot support
  set {
    name  = "global.snapshot.enabled"
    value = "true"
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    # module.k10_tls,
  ]
}

resource "kubectl_manifest" "k10_istio_gateway" {
  count     = var.enable_k10 ? 1 : 0
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: k10-gateway
  namespace: ${var.k10_namespace}
spec:
  selector:
    istio: ingressgateway  # This matches the Istio ingress gateway service
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: k10-https-cert  # Must exist in the same namespace as istio ingress gateway (default is istio-system)
      hosts:
        - k10.${var.base_domain}
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.k10_deployment,
    helm_release.cert_manager,
    helm_release.istio_ingress,
    kubectl_manifest.k10-certificate
  ]
}
resource "kubectl_manifest" "k10_virtualservice" {
  count     = var.enable_k10 ? 1 : 0
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: k10
  namespace: ${var.k10_namespace}
spec:
  hosts:
    - k10.${var.base_domain}
  gateways:
    - k10-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: gateway.${var.k10_namespace}.svc.cluster.local
            port:
              number: 80
YAML
  depends_on = [
    kubectl_manifest.k10_istio_gateway,
  ]
}

resource "kubectl_manifest" "k10-certificate" {
  count     = var.enable_k10 ? 1 : 0
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: k10-tls-certificate
  namespace: istio-system
spec:
  secretName: k10-https-cert
  dnsNames:
    - "k10.${var.base_domain}"
  issuerRef:
    name: root-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io  # REQUIRED field
YAML
  depends_on = [
    kubectl_manifest.root_ca_issuer,
  ]
}