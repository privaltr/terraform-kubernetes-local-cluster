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

# Vault PVC for Permanent Storage
resource "kubectl_manifest" "vault_pvc" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: vault-pvc
  namespace: ${var.vault_namespace}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: "standard"  # Adjust according to your environment
  volumeName: vault-pv  # Explicitly bind to our PV
YAML
  depends_on = [
    kind_cluster.default
  ]
}

resource "kubectl_manifest" "vault_pv" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: vault-pv
spec:
  storageClassName: standard
  capacity:
    storage: 5Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data/vault-pv  # Must exist on the Kind node
YAML
}

# Vault Helm Release
resource "helm_release" "vault_deployment" {
  count            = var.enable_vault ? 1 : 0
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.29.1"
  namespace        = var.vault_namespace
  create_namespace = true

  set {
    name  = "server.dev.enabled"
    value = "false"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.service.port"
    value = 8200
  }

  # Disable StatefulSet/HA mode
  set {
    name  = "server.standalone.enabled"
    value = "true"  # Force Deployment instead of StatefulSet
  }

  set {
    name  = "server.ha.enabled"
    value = "false"  # Explicitly disable HA
  }

  # Explicitly disable StatefulSet (critical!)
  set {
    name  = "server.statefulSet.enabled"
    value = "false"
  }

  # Storage settings
  set {
    name  = "server.dataStorage.enabled"
    value = "false"  # Enable storage
  }

  set {
    name  = "server.dataStorage.existingClaim"
    value = "vault-pvc"  # Your manual PVC
  }

  set {
    name  = "server.dataStorage.create"
    value = "false"  # Block Helm from creating PVCs
  }

  # Explicit volume mounts
  set {
    name  = "server.volumes[0].name"
    value = "vault-data"
  }

  set {
    name  = "server.volumes[0].persistentVolumeClaim.claimName"
    value = "vault-pvc"
  }

  set {
    name  = "server.volumeMounts[0].name"
    value = "vault-data"
  }

  set {
    name  = "server.volumeMounts[0].mountPath"
    value = "/vault/data"
  }

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    kubectl_manifest.vault_pvc,
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
