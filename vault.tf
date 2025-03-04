# Vault Namespace Creation
resource "kubectl_manifest" "vault_namespace" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.vault_namespace}
YAML
  depends_on = [
    kind_cluster.default
  ]
}

# Vault TLS Module
module "vault_tls" {
  count     = var.enable_vault ? 1 : 0
  source    = "./modules/tls-cert"
  namespace = var.vault_namespace
  dns_names = [
    "vault.${var.base_domain}"
  ]
  certs_path = var.certs_path

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
  ]
}

# Vault Helm Release
resource "helm_release" "vault_deployment" {
  count            = var.enable_vault ? 1 : 0
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = var.vault_namespace
  create_namespace = true

  set {
    name  = "server.dev.enabled"
    value = "true"
  }

  set {
    name  = "server.dev.devRootToken"
    value = "root"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.service.port"
    value = 8200
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    # kubectl_manifest.vault_service,
    module.vault_tls,
  ]
}

# Vault Ingress
resource "kubectl_manifest" "vault_ingress" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: projectcontour.io/v1
kind: HTTPProxy
metadata:
  name: vault
  namespace: ${var.vault_namespace}
spec:
  virtualhost:
    fqdn: vault.${var.base_domain}
    tls:
      secretName: ${module.vault_tls[0].cert_secret}
  routes:
    - conditions:
      - prefix: /
      services:
        - name: vault
          port: 8200
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    helm_release.vault_deployment,
    module.vault_tls,
  ]
}
