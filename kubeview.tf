locals {
  kubeview_cert_secret = "kubeview-https-cert"
}

# Vault Namespace Creation
resource "kubectl_manifest" "kubeview_namespace" {
  count     = var.enable_kubeview ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.kubeview_namespace}
YAML
  depends_on = [
    kind_cluster.default,
    # kubectl_manifest.Internal-only-NetworkPolicy
  ]
}

resource "helm_release" "kubeview" {
  count     = var.enable_kubeview ? 1 : 0
  name             = "kubeview"
  repository       = "https://kubeview.benco.io/charts"
  chart            = "kubeview"
  version          = "0.1.31" # Check for the latest version
  namespace        = "${var.kubeview_namespace}"
  create_namespace = true

  set {
    name  = "image.pullPolicy"
    value = "IfNotPresent"
  }

  set {
    name  = "ingress.enabled"
    value = "false" # We'll handle ingress with Istio
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,]
}

resource "kubectl_manifest" "patch_kubeview_service" {
  count     = var.enable_kubeview ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: kubeview
  namespace: ${var.kubeview_namespace}
spec:
  type: ClusterIP
YAML

  depends_on = [
    helm_release.kubeview
  ]
}


resource "kubectl_manifest" "kubeview_virtualservice" {
  count     = var.enable_kubeview ? 1 : 0
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kubeview
  namespace: ${var.kubeview_namespace}
spec:
  hosts:
    - kubeview.${var.base_domain}
  gateways:
    - kubeview-gateway
  http:
    - match:
      - uri:
          prefix: /
      route:
      - destination:
          host: kubeview.${var.kubeview_namespace}.svc.cluster.local
          port:
            number: 80
YAML
  depends_on = [
    kubectl_manifest.kubeview_istio_gateway,
    helm_release.kubeview
  ]
}

resource "kubectl_manifest" "kubeview_istio_gateway" {
  count     = var.enable_kubeview ? 1 : 0
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: kubeview-gateway
  namespace: ${var.kubeview_namespace}
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: ${local.kubeview_cert_secret}
      hosts:
        - kubeview.${var.base_domain}
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.vault_deployment,
    helm_release.cert_manager,
    helm_release.istio_ingress,
    kubectl_manifest.kubeview_certificate
  ]
}

resource "kubectl_manifest" "kubeview_certificate" {
  count     = var.enable_kubeview ? 1 : 0
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kubeview-tls-certificate
  namespace: istio-system
spec:
  secretName: ${local.kubeview_cert_secret}
  dnsNames:
    - "kubeview.${var.base_domain}"
  issuerRef:
    name: root-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
YAML
  depends_on = [
    helm_release.cert_manager
  ]
}