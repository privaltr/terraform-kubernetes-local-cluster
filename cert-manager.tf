data "kubectl_path_documents" "cert_manager_crd" {
  pattern = "${path.module}/kubernetes/cert_manager_crds/*.yml"
}

resource "kubectl_manifest" "cert_manager_crd" {
  for_each          = data.kubectl_path_documents.cert_manager_crd.manifests
  yaml_body         = each.value
  server_side_apply = true

  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
  ]
}

# https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/README.template.md
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.12.4"
  namespace        = var.cert_manager_namespace
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "false"
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
  ]
}


### this is currenlty kinda double, check the module tls. It's not double as it's really a module
# Root CA Secret (store your actual cert/key in variables or a secrets manager)
resource "kubectl_manifest" "root_ca_secret" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Secret
    metadata:
      name: root-cert
      namespace: ${var.cert_manager_namespace}
    type: kubernetes.io/tls
    data:
      tls.key: "${filebase64("${var.certs_path}/rootCA-key.pem")}"
      tls.crt: "${filebase64("${var.certs_path}/rootCA.pem")}"
  YAML

  depends_on = [helm_release.cert_manager]
}

# Root CA ClusterIssuer
resource "kubectl_manifest" "root_ca_issuer" {
  yaml_body = <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: root-ca-issuer
spec:
  ca:
    secretName: root-cert
YAML

  depends_on = [
    kubectl_manifest.root_ca_secret,
    helm_release.cert_manager
  ]
}