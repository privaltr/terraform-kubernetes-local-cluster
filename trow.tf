# https://github.com/ContainerSolutions/trow/blob/main/docs/HELM_INSTALL.md
resource "helm_release" "trow" {
  count            = var.use_trow ? 1 : 0
  name             = "trow"
  repository       = "https://trow.io"
  chart            = "trow"
  version          = "0.3.5"
  namespace        = var.trow_namespace
  create_namespace = true

  set {
    name  = "ingress.enabled"
    value = "false"  # Since you're using Istio
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
  ]
}

resource "kubectl_manifest" "registry_config_map" {
  count     = var.use_trow ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "trow.${var.base_domain}"
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.trow,
    # helm_release.contour,
    helm_release.cert_manager,
    # module.trow_tls,
    kubectl_manifest.trow_certificate
  ]
}

locals {
  trow_cert_secret = "trow-https-cert"
}

resource "kubectl_manifest" "trow_virtualservice" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: trow
  namespace: ${var.trow_namespace}
spec:
  hosts:
    - trow.${var.base_domain}
  gateways:
    - trow-gateway
  http:
    - match:
      - uri:
          prefix: /
      route:
      - destination:
          host: trow.${var.trow_namespace}.svc.cluster.local
          port:
            number: 8000
YAML
  depends_on = [
    kubectl_manifest.trow_istio_gateway,
    helm_release.trow
  ]
}

resource "kubectl_manifest" "trow_istio_gateway" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: trow-gateway
  namespace: ${var.trow_namespace}
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
        credentialName: ${local.trow_cert_secret}
      hosts:
        - trow.${var.base_domain}
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.vault_deployment,
    helm_release.cert_manager,
    helm_release.istio_ingress,
    kubectl_manifest.trow_certificate
  ]
}

resource "kubectl_manifest" "trow_certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: trow-tls-certificate
  namespace: istio-system
spec:
  secretName: ${local.trow_cert_secret}
  dnsNames:
    - "trow.${var.base_domain}"
  issuerRef:
    name: root-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
YAML
  depends_on = [
    helm_release.cert_manager
  ]
}