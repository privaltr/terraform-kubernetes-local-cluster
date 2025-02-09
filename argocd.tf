data "kubectl_path_documents" "argo_crd" {
  pattern = "${path.module}/kubernetes/argocd_crds/*.yml"
}

resource "kubectl_manifest" "argo_crd" {
  for_each          = data.kubectl_path_documents.argo_crd.manifests
  yaml_body         = each.value
  server_side_apply = true

  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
  ]
}

# https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.8.0"
  namespace        = var.argocd_namespace
  create_namespace = true

  set {
    name  = "crds.install"
    value = "false"
  }

  values = [<<YAML
configs:
  cm:
    "accounts.kind_cluster": "apiKey,login"
    "kustomize.buildOptions": "--enable-alpha-plugins"
    "plugin.argocd-vault-plugin": |
      name: argocd-vault-plugin
      generate:
        command: ["argocd-vault-plugin"]
        args: ["generate", "./"]
params:
  server.insecure: true
secret:
  createSecret: true
  argocdServerAdminPassword: "$2a$10$KVscBZGucWmkXd5HtFwSHeVGKrKJM9EfRotC9N.V6tbwrftV3ab.a"
  argocdServerAdminPasswordMtime: "2023-02-22T21:33:46Z"
  extra:
    "accounts.kind_cluster.tokens": "[{\"id\":\"kind_cluster\",\"iat\":1693879545}]"
repoServer:  # <-- Top-level key
  env:
    - name: VAULT_SKIP_VERIFY
      value: "true"
    - name: ARGOCD_ENABLE_VAULT_PLUGIN
      value: "true"
    - name: VAULT_ADDR
      value: "http://vault.default.svc.cluster.local:8200"
    - name: VAULT_TOKEN
      value: "root"
  extraInitContainers:  # <-- Directly under repoServer
    - name: install-vault-plugin
      image: alpine:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          wget -O /custom-tools/argocd-vault-plugin https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v1.7.0/argocd-vault-plugin_1.7.0_linux_amd64
          chmod +x /custom-tools/argocd-vault-plugin
      volumeMounts:
        - name: custom-tools
          mountPath: /custom-tools
  volumes:
    - name: custom-tools
      emptyDir: {}
  volumeMounts:
    - name: custom-tools
      mountPath: /usr/local/bin/argocd-vault-plugin  # Mount to the same path as the plugin binary
      subPath: argocd-vault-plugin
YAML
  ]
  depends_on = [
    kind_cluster.default,
    helm_release.cilium,
    kubectl_manifest.argo_crd,
  ]
}

module "argo_tls" {
  source    = "./modules/tls-cert"
  namespace = helm_release.argocd.namespace
  dns_names = [
    "argocd.${var.base_domain}"
  ]
  certs_path = var.certs_path

  depends_on = [
    kind_cluster.default,
    helm_release.argocd,
    helm_release.cert_manager,
    kubectl_manifest.argo_crd,
  ]
}

resource "kubectl_manifest" "argocd_ingress" {
  yaml_body = <<YAML
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: argo
  namespace: ${helm_release.argocd.namespace}
spec:
  virtualhost:
    fqdn: argocd.${var.base_domain}
    tls:
      secretName: ${module.argo_tls.cert_secret}
  routes:
    - conditions:
      - prefix: /
      services:
        - name: argocd-server
          port: 80

YAML
  depends_on = [
    kind_cluster.default,
    helm_release.argocd,
    helm_release.contour,
    helm_release.cert_manager,
    kubectl_manifest.argo_crd,
    module.argo_tls,
  ]
}
