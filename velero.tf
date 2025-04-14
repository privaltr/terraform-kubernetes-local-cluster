# Velero Namespace Creation
resource "kubectl_manifest" "velero_namespace" {
  count     = var.enable_velero ? 1 : 0
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${var.velero_namespace}
YAML
  depends_on = [
    kind_cluster.default
  ]
}

# Velero TLS Module (for secure communication)
module "velero_tls" {
  count     = var.enable_velero ? 1 : 0
  source    = "./modules/tls-cert"
  namespace = var.velero_namespace
  dns_names = [
    "velero.${var.base_domain}"
  ]
  certs_path = var.certs_path

  depends_on = [
    kind_cluster.default,
    helm_release.cert_manager,
  ]
}

# MinIO Deployment for local storage (S3-compatible)
resource "helm_release" "minio" {
  count      = var.enable_velero ? 1 : 0
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.4.0" # Controleer of dit de meest recente versie is
  namespace  = var.velero_namespace






  set {
    name  = "mode"
    value = "standalone"  # Critical: Run as single pod
  }

  set {
    name  = "persistence.enabled"
    value = "false"       # Disable PVC for testing (optional)
  }

  # set {
  #   name  = "replicas"
  #   value = "2"  # Fewer pods (adjust based on your cluster size)
  # }
  
  # set {
  #   name  = "persistence.enabled"
  #   value = "true"
  # }
  set {
    name  = "persistence.size"
    value = "50Gi"
  }
  set {
    name  = "rootUser"
    value = "minio"
  }
  set {
    name  = "rootPassword"
    value = "minio123"
  }

  set {
    name  = "policies[0].name"
    value = "velero"
  }
  set {
    name  = "policies[0].statements[0].resources[0]"
    value = "arn:aws:s3:::velero"
  }
  set {
    name  = "policies[0].statements[0].actions[0]"
    value = "s3:ListBucket"
  }
  set {
    name  = "policies[0].statements[0].actions[1]"
    value = "s3:GetBucketLocation"
  }
  set {
    name  = "policies[0].statements[1].resources[0]"
    value = "arn:aws:s3:::velero/*"
  }
  set {
    name  = "policies[0].statements[1].actions[0]"
    value = "s3:GetObject"
  }
  set {
    name  = "policies[0].statements[1].actions[1]"
    value = "s3:PutObject"
  }
  set {
    name  = "policies[0].statements[1].actions[2]"
    value = "s3:DeleteObject"
  }


  set {
    name  = "users[0].accessKey"
    value = "CW1ULP6uujWiQwVrMCRU"
  }
  set {
    name  = "users[0].secretKey"
    value = "6qHOwiRpPmapEyb02gKfx2zJ0iEAVD9y1xqqon5P"
  }
  set {
    name  = "users[0].policy"
    value = "velero"
  }

  set {
    name  = "buckets[0].name"
    value = "velero"
  }
  set {
    name  = "buckets[0].policy"
    value = "none"
  }
  set {
    name  = "buckets[0].purge"
    value = "false"
  }
  depends_on = [
    kubectl_manifest.velero_namespace
  ]
}

# Velero Helm Release
resource "helm_release" "velero" {
  count      = var.enable_velero ? 1 : 0
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  version    = "5.0.2"
  namespace  = var.velero_namespace






  # CORS Configuration
  set {
    name  = "configuration.extraEnvVars[0].name"
    value = "VELERO_CORS_ORIGIN"
  }

  set {
    name  = "configuration.extraEnvVars[0].value"
    value = "https://velero-ui.${var.base_domain}" # Or "*" for testing
  }


  # Enable API service
  # set {
  #   name  = "service.enabled"
  #   value = "true"
  # }

  # set {
  #   name  = "service.type"
  #   value = "ClusterIP"
  # }

  # set {
  #   name  = "service.port"
  #   value = "8085"
  # }

  # CRD handling
  set {
    name  = "upgradeCRDs"
    value = "false"
  }
  set {
    name  = "installCRDs"
    value = "true"
  }

  # Backup Storage Location Configuration
  set {
    name  = "configuration.backupStorageLocation[0].name"
    value = "default"
  }
  set {
    name  = "configuration.backupStorageLocation[0].provider"
    value = "aws"
  }
  set {
    name  = "configuration.backupStorageLocation[0].bucket"
    value = "velero"
  }
  set {
    name  = "configuration.backupStorageLocation[0].config.region"
    value = "minio"
  }
  set {
    name  = "configuration.backupStorageLocation[0].config.s3Url"
    value = "http://minio.${var.velero_namespace}.svc.cluster.local:9000"
  }
  set {
    name  = "configuration.backupStorageLocation[0].config.s3ForcePathStyle"
    value = "true"
  }
  set {
    name  = "configuration.backupStorageLocation[0].config.publicUrl"
    value = "http://minio.${var.velero_namespace}.svc.cluster.local:9000"
  }

  # Volume Snapshot Location Configuration (required even if not used)
  set {
    name  = "configuration.volumeSnapshotLocation[0].name"
    value = "default"
  }
  set {
    name  = "configuration.volumeSnapshotLocation[0].provider"
    value = "aws"
  }
  set {
    name  = "configuration.volumeSnapshotLocation[0].config.region"
    value = "minio"
  }

  # Credentials
  set {
    name  = "credentials.secretContents.cloud"
    value = <<EOF
[default]
aws_access_key_id=CW1ULP6uujWiQwVrMCRU
aws_secret_access_key=6qHOwiRpPmapEyb02gKfx2zJ0iEAVD9y1xqqon5P
EOF
  }

  # AWS Plugin
  set {
    name  = "initContainers[0].name"
    value = "velero-plugin-for-aws"
  }
  set {
    name  = "initContainers[0].image"
    value = "velero/velero-plugin-for-aws:v1.7.0"
  }
  set {
    name  = "initContainers[0].volumeMounts[0].mountPath"
    value = "/target"
  }
  set {
    name  = "initContainers[0].volumeMounts[0].name"
    value = "plugins"
  }

  # Features (optional but recommended)
  set {
    name  = "features"
    value = "EnableCSI"
  }

  depends_on = [
    helm_release.minio,
    kubectl_manifest.velero_namespace
  ]
}

# Velero UI Helm Release using the official OTWLD chart
# resource "helm_release" "velero-ui" {
#   count      = var.enable_velero ? 1 : 0
#   name       = "velero-ui"
#   repository = "https://helm.otwld.com/"
#   chart      = "velero-ui"
#   version    = "0.9.0" # Use the appropriate version
#   namespace  = var.velero_namespace



#  # Required configuration
#   set {
#     name  = "configuration.general.veleroNamespace"
#     value = var.velero_namespace
#   }

#   set {
#     name  = "configuration.general.secretPassPhrase.value"
#     value = "admin" # Should be a secure random string
#   }

#   # Velero server connection
#   # set {
#   #   name  = "service.type"
#   #   value = "ClusterIP"
#   # }

#   set {
#     name  = "service.port"
#     value = 3000
#   }

#   # Image configuration
#   # set {
#   #   name  = "image.repository"
#   #   value = "otwld/velero-ui"
#   # }

#   # # set {
#   # #   name  = "image.tag"
#   # #   value = "latest" # Pin to specific version in production
#   # # }

#   # set {
#   #   name  = "image.pullPolicy"
#   #   value = "IfNotPresent"
#   # }

#   # RBAC configuration
#   set {
#     name  = "rbac.create"
#     value = "true"
#   }

#   set {
#     name  = "rbac.clusterAdministrator"
#     value = "true"
#   }

#   # Health checks
#   set {
#     name  = "livenessProbe.enabled"
#     value = "true"
#   }

#   set {
#     name  = "readinessProbe.enabled"
#     value = "true"
#   }

#   # Ingress disabled (using Contour HTTPProxy)
#   set {
#     name  = "ingress.enabled"
#     value = "false"
#   }

#   # Security context
#   # set {
#   #   name  = "securityContext.runAsNonRoot"
#   #   value = "true"
#   # }

#   # set {
#   #   name  = "securityContext.runAsUser"
#   #   value = "1000"
#   # }

#   # # Additional environment variables
#   # set {
#   #   name  = "env[0].name"
#   #   value = "NODE_ENV"
#   # }

#   # set {
#   #   name  = "env[0].value"
#   #   value = "production"
#   # }

#   depends_on = [
#     helm_release.velero,
#     kubectl_manifest.velero_namespace
#   ]
# }


# # Velero GUI Ingress
# resource "kubectl_manifest" "velero_gui_ingress" {
#   count     = var.enable_velero ? 1 : 0
#   yaml_body = <<YAML
# apiVersion: projectcontour.io/v1
# kind: HTTPProxy
# metadata:
#   annotations:
#     kubernetes.io/ingress.class: contour
#   name: velero-gui-ingress
#   namespace: ${var.velero_namespace}
# spec:
#   virtualhost:
#     fqdn: velero.${var.base_domain}
#     tls:
#       secretName: ${module.velero_tls[0].cert_secret}
#   routes:
#     - conditions:
#         - prefix: /
#       enableWebsockets: true
#       services:
#         - name: velero-ui
#           port: 3000
# YAML
#   depends_on = [
#     # helm_release.velero_gui,
#     module.velero_tls,
#   ]
# }
