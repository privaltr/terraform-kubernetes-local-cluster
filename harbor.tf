resource "helm_release" "harbor" {
  count            = var.use_harbor ? 1 : 0
  name             = "harbor"
  repository       = "https://helm.goharbor.io"
  chart            = "harbor"
  version          = "1.17.0" # Check for latest version
  namespace        = var.harbor_namespace
  create_namespace = true

  set {
    name  = "expose.type"
    value = "clusterIP" # Using Istio for ingress
  }

  set {
    name  = "expose.tls.enabled"
    value = "false" # Let Istio handle TLS
  }

  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "externalURL"
    value = "https://harbor.${var.base_domain}"
  }

  set {
    name  = "harborAdminPassword"
    value = "admin"
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
  ]
}

resource "kubectl_manifest" "harbor_registry_config_map" {
  count     = var.use_harbor ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "harbor.${var.base_domain}"
    help: "https://harbor.${var.base_domain}/harbor/projects"
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.harbor,
    helm_release.cert_manager,
    kubectl_manifest.harbor_certificate
  ]
}

locals {
  harbor_cert_secret = "harbor-https-cert"
}

resource "kubectl_manifest" "harbor_virtualservice" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: harbor
  namespace: ${var.harbor_namespace}
spec:
  hosts:
    - "harbor.${var.base_domain}"
  gateways:
    - harbor-gateway
  http:
    - match:
      - uri:
          prefix: /api/
      - uri:
          prefix: /service/
      - uri:
          prefix: /v2/
      - uri:
          prefix: /c/
      route:
      - destination:
          host: harbor-core.${var.harbor_namespace}.svc.cluster.local
          port:
            number: 80
    - match:
      - uri:
          prefix: /
      route:
      - destination:
          host: harbor-portal.${var.harbor_namespace}.svc.cluster.local
          port:
            number: 80
YAML
  depends_on = [helm_release.harbor]
}

resource "kubectl_manifest" "harbor_istio_gateway" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: harbor-gateway
  namespace: ${var.harbor_namespace}
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
        credentialName: ${local.harbor_cert_secret}
      hosts:
        - "harbor.${var.base_domain}"
YAML
  depends_on = [
    helm_release.istio_ingress,
    kubectl_manifest.harbor_certificate
  ]
}

resource "kubectl_manifest" "harbor_certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: harbor-tls-certificate
  namespace: istio-system
spec:
  secretName: ${local.harbor_cert_secret}
  dnsNames:
    - "harbor.${var.base_domain}"
  issuerRef:
    name: root-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io
YAML
  depends_on = [
    helm_release.cert_manager
  ]
}