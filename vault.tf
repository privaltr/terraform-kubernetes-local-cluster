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

# Vault Service
resource "kubectl_manifest" "vault_service" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Service
metadata:
  name: vault
  namespace: ${var.vault_namespace}
  labels:
    app: vault
    service: vault
spec:
  ports:
  - name: http
    port: 8200
    targetPort: 8200
  selector:
    app: vault
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    kubectl_manifest.argo_crd,
    module.vault_tls,
  ]
}

# Vault Deployment
resource "kubectl_manifest" "vault_deployment" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault
  namespace: ${var.vault_namespace}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault
      version: v1
  template:
    metadata:
      labels:
        app: vault
        version: v1
    spec:
      containers:
      - image: hashicorp/vault:latest
        imagePullPolicy: IfNotPresent
        name: vault
        ports:
        - containerPort: 8200
        env:
        - name: VAULT_DEV_ROOT_TOKEN_ID
          value: "root"
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    kubectl_manifest.vault_service,
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
    kubectl_manifest.vault_deployment,
    module.vault_tls,
  ]
}
