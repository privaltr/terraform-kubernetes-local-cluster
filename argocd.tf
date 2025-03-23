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
  params:
    server.insecure: true
  secret:
    createSecret: true

    argocdServerAdminPassword: "$2a$10$KVscBZGucWmkXd5HtFwSHeVGKrKJM9EfRotC9N.V6tbwrftV3ab.a"
    argocdServerAdminPasswordMtime: "2023-02-22T21:33:46Z"

    extra:
      # API Token = eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJhcmdvY2QiLCJzdWIiOiJydWJyaWthOmFwaUtleSIsIm5iZiI6MTY5Mzg3OTU0NSwiaWF0IjoxNjkzODc5NTQ1LCJqdGkiOiJydWJyaWthLXRpbHQifQ.SIjQqXR2bT0wwOPRJEHSSTRi9Er-1qxGDOTyyQBSnO0
      "accounts.kind_cluster.tokens": "[{\"id\":\"kind_cluster\",\"iat\":1693879545}]"  
server:
  insecure: true  # Allow HTTP access
  extraArgs:
    - --insecure  # Disable HTTPS enforcement
repoServer:  # <-- Top-level key
  volumes:
    - name: custom-tools
      emptyDir: {}
  volumeMounts:
    - name: custom-tools
      mountPath: /usr/local/bin/argocd-vault-plugin
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

resource "kubectl_manifest" "cmp_plugin" {
  yaml_body = <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: cmp-plugin
  namespace: ${helm_release.argocd.namespace}
data:
  avp.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-vault-plugin
    spec:
      allowConcurrency: true
      discover:
        find:
          command:
            - sh
            - "-c"
            - "find . -name '*.yaml' | xargs -I {} grep \"<path\\|avp\\.kubernetes\\.io\" {} | grep ."
      generate:
        command:
          - argocd-vault-plugin
          - generate
          - "."
      lockRepo: false
YAML
}

resource "kubectl_manifest" "argocd_repo_server_deployment" {
  yaml_body = <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-repo-server
  namespace: ${helm_release.argocd.namespace}
spec:
  template:
    spec:
      automountServiceAccountToken: true
      volumes:
        - configMap:
            name: cmp-plugin
          name: cmp-plugin
        - name: custom-tools
          emptyDir: {}
      initContainers:
      - name: download-tools
        image: registry.access.redhat.com/ubi8
        env:
          - name: AVP_VERSION
            value: 1.16.1
        command: [sh, -c]
        args:
          - >-
            curl -L https://github.com/argoproj-labs/argocd-vault-plugin/releases/download/v$(AVP_VERSION)/argocd-vault-plugin_$(AVP_VERSION)_linux_amd64 -o argocd-vault-plugin &&
            chmod +x argocd-vault-plugin &&
            mv argocd-vault-plugin /custom-tools/
        volumeMounts:
          - mountPath: /custom-tools
            name: custom-tools
      containers:
      - name: avp
        command: [/var/run/argocd/argocd-cmp-server]
        image: registry.access.redhat.com/ubi8
        securityContext:
          runAsNonRoot: true
          runAsUser: 999
        volumeMounts:
          - mountPath: /var/run/argocd
            name: var-files
          - mountPath: /home/argocd/cmp-server/plugins
            name: plugins
          - mountPath: /tmp
            name: tmp

          # Register plugins into sidecar
          - mountPath: /home/argocd/cmp-server/config/plugin.yaml
            subPath: avp.yaml
            name: cmp-plugin

          # Important: Mount tools into $PATH
          - name: custom-tools
            subPath: argocd-vault-plugin
            mountPath: /usr/local/bin/argocd-vault-plugin
        env:
          - name: AVP_TYPE
            value: "vault"
          - name: AVP_AUTH_TYPE
            value: "userpass"
            # value: "kubernetes"
            # value: "token"
          - name: AVP_USERNAME
            value: "argocd"
          - name: AVP_PASSWORD
            value: "root"
          - name: VAULT_ROLE
            value: "argocd"
          - name: VAULT_SKIP_VERIFY
            value: "true"
          - name: ARGOCD_ENABLE_VAULT_PLUGIN
            value: "true"
          - name: VAULT_ADDR
            value: "http://vault.${var.vault_namespace}.svc.cluster.local:8200"  # Adjust based on your Vault URL
          # - name: VAULT_TOKEN
          #   value: "root"
YAML
}