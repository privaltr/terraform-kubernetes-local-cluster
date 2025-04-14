# https://github.com/ContainerSolutions/trow/blob/main/docs/HELM_INSTALL.md
resource "helm_release" "trow" {
  count            = var.use_trow ? 1 : 0
  name             = "trow"
  repository       = "https://trow.io"
  chart            = "trow"
  version          = "0.3.5"
  namespace        = var.trow_namespace
  create_namespace = true

  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
  ]
}

module "trow_tls" {
  count     = var.use_trow ? 1 : 0
  source    = "./modules/tls-cert"
  namespace = var.trow_namespace
  dns_names = [
    "trow.${var.base_domain}"
  ]
  certs_path = var.certs_path

  depends_on = [
    kind_cluster.default,
    helm_release.trow,
    helm_release.cert_manager,
  ]
}

resource "kubectl_manifest" "trow_ingress" {
  count     = var.use_trow ? 1 : 0
  yaml_body = <<YAML
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: trow
  namespace: ${var.trow_namespace}
spec:
  virtualhost:
    fqdn: trow.${var.base_domain}
    tls:
      secretName: ${module.trow_tls[0].cert_secret}
  routes:
    - conditions:
      - prefix: /
      services:
        - name: trow
          port: 8000

YAML
  depends_on = [
    kind_cluster.default,
    helm_release.trow,
    helm_release.contour,
    helm_release.cert_manager,
    module.trow_tls,
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
    helm_release.contour,
    helm_release.cert_manager,
    module.trow_tls,
  ]
}