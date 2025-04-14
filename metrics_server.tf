resource "helm_release" "metrics_server" {
  count     = var.enable_metrics_server ? 1 : 0
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.0"  # Pin to a stable version

  # TODO I suppose
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  depends_on = [
    kind_cluster.default,  # Wait for KinD to be ready
  ]
}