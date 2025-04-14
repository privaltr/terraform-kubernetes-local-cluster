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
  namespace = "istio-system"
  dns_names = [
    "vault.${var.base_domain}"
  ]
  certs_path = var.certs_path

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
  ]
}

# # Vault PVC for Permanent Storage
# resource "kubectl_manifest" "vault_pvc" {
#   count     = var.enable_vault ? 1 : 0
#   yaml_body = <<YAML
# apiVersion: v1
# kind: PersistentVolumeClaim
# metadata:
#   name: vault-pvc
#   namespace: ${var.vault_namespace}
#   labels:
#     app.kubernetes.io/instance: vault
#     app.kubernetes.io/name: vault
#     component: server
#   annotations:
#     pv.kubernetes.io/bind-completed: "yes"
#     pv.kubernetes.io/bound-by-controller: "yes"
#     volume.kubernetes.io/storage-provisioner: rancher.io/local-path
#     volume.kubernetes.io/selected-node: kind-control-plane
# spec:
#   storageClassName: "standard"  # Adjust according to your environment
#   accessModes:
#     - ReadWriteOnce
#   resources:
#     requests:
#       storage: 5Gi
#   volumeName: vault-pv  # Explicitly bind to our PV
# YAML
#   depends_on = [
#     kind_cluster.default
#   ]
# }

# resource "kubectl_manifest" "vault_pv" {
#   count     = var.enable_vault ? 1 : 0
#   yaml_body = <<YAML
# apiVersion: v1
# kind: PersistentVolume
# metadata:
#   name: vault-pv
#   annotations:
#     pv.kubernetes.io/bound-by-controller: "yes"
# spec:
#   storageClassName: standard
#   capacity:
#     storage: 5Gi
#   accessModes:
#     - ReadWriteOnce
#   persistentVolumeReclaimPolicy: Retain
#   hostPath:
#     path: /data/vault-pv  # Must exist on the Kind node
#     type: DirectoryOrCreate
# YAML
# }

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
    value = "true"  # Enable storage
  }

  set {
    name  = "server.dataStorage.create"
    value = "true"  # Block Helm from creating PVCs
  }

  set {
    name  = "server.dataStorage.existingClaim"
    value = "vault-pvc"  # Your manual PVC
  }


  # #Explicit volume mounts
  # set {
  #   name  = "server.volumes[0].name"
  #   value = "vault-data"
  # }

  # set {
  #   name  = "server.volumes[0].persistentVolumeClaim.claimName"
  #   value = "vault-pvc"
  # }

  # set {
  #   name  = "server.volumeMounts[0].name"
  #   value = "vault-data"
  # }

  # set {
  #   name  = "server.volumeMounts[0].mountPath"
  #   value = "/vault/data"
  # }

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
    # kubectl_manifest.vault_pvc,
    module.vault_tls,
  ]
}

# # Vault Ingress
# resource "kubectl_manifest" "vault_ingress" {
#   count     = var.enable_vault ? 1 : 0
#   yaml_body = <<YAML
# apiVersion: projectcontour.io/v1
# kind: HTTPProxy
# metadata:
#   name: vault
#   namespace: ${var.vault_namespace}
# spec:
#   virtualhost:
#     fqdn: vault.${var.base_domain}
#     tls:
#       secretName: ${module.vault_tls[0].cert_secret}
#   routes:
#     - conditions:
#       - prefix: /
#       services:
#         - name: vault
#           port: 8200
# YAML
#   depends_on = [
#     kind_cluster.default,
#     helm_release.cert_manager,
#     helm_release.vault_deployment,
#     module.vault_tls,
#   ]
# }



resource "kubectl_manifest" "vault_istio_gateway" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: vault-gateway
  namespace: ${var.vault_namespace}
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
        credentialName: ${module.vault_tls[0].cert_secret}  # Must exist in the same namespace as istio ingress gateway (default is istio-system)
      hosts:
        - vault.${var.base_domain}
YAML
  depends_on = [
    kind_cluster.default,
    helm_release.vault_deployment,
    helm_release.cert_manager,
    module.vault_tls,
    helm_release.istio_ingress,
  ]
}
resource "kubectl_manifest" "vault_virtualservice" {
  count     = var.enable_vault ? 1 : 0
  yaml_body = <<YAML
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: vault
  namespace: ${var.vault_namespace}
spec:
  hosts:
    - vault.${var.base_domain}
  gateways:
    - vault-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: vault.${var.vault_namespace}.svc.cluster.local
            port:
              number: 8200
YAML
  depends_on = [
    kubectl_manifest.vault_istio_gateway
  ]
}