locals {
  cilium_cert_secret = "cilium-https-cert"
}

resource "helm_release" "cilium" {
  count            = var.use_cilium ? 1 : 0
  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  chart            = "cilium"
  version          = "1.14.1"
  namespace        = var.cilium_namespace
  create_namespace = true

  set {
    name  = "image.pullPolicy"
    value = "IfNotPresent"
  }

  set {
    name  = "ipam.mode"
    value = "kubernetes"
  }

  set {
    name  = "hubble.enabled"
    value = "true"
  }

  set {
    name  = "hubble.ui.enabled"
    value = "true"
  }

  set {
    name  = "hubble.relay.enabled"
    value = "true"
  }
  # Make sure `kind` has written the `kubeconfig` before we move forward
  # with installing helm.
  depends_on = [kind_cluster.default]
}

resource "kubectl_manifest" "hubble_grpc_service" {
  count     = var.use_cilium ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: hubble-ui-grpc
  namespace: ${helm_release.cilium[0].namespace}
spec:
  ports:
  - name: grpc
    port: 80
    protocol: TCP
    targetPort: 8090
  selector:
    k8s-app: hubble-ui
  type: ClusterIP
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
    # helm_release.contour,
    helm_release.cert_manager,
  ]
}

resource "kubectl_manifest" "cilium_virtualservice" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: hubble-ui
  namespace: ${helm_release.cilium[0].namespace}
spec:
  hosts:
    - hubble.${var.base_domain}
  gateways:
    - hubble-gateway
  http:
    - match:
        - uri:
            prefix: /api
      route:
        - destination:
            host: hubble-ui-grpc.${helm_release.cilium[0].namespace}.svc.cluster.local
            port:
              number: 80
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: hubble-ui.${helm_release.cilium[0].namespace}.svc.cluster.local
            port:
              number: 80
YAML
  depends_on = [
    kubectl_manifest.hubble_istio_gateway
  ]
}

resource "kubectl_manifest" "hubble_istio_gateway" {
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: hubble-gateway
  namespace: ${helm_release.cilium[0].namespace}
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
        credentialName: hubble-https-cert  # Must exist in the same namespace as istio ingress gateway (default is istio-system)
      hosts:
        - hubble.${var.base_domain}
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
    helm_release.cert_manager,
    # module.cilium_tls,
    helm_release.istio_ingress,
    kubectl_manifest.hubble-certificate
  ]
}

resource "kubectl_manifest" "hubble-certificate" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: hubble-tls-certificate
  namespace: istio-system
spec:
  secretName: hubble-https-cert
  dnsNames:
    - "hubble.${var.base_domain}"
  issuerRef:
    name: root-ca-issuer
    kind: ClusterIssuer
    group: cert-manager.io  # REQUIRED field
YAML
  depends_on = [
    kubectl_manifest.root_ca_issuer,
  ]
}
