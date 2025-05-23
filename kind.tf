locals {
  containerd_config_path = "/etc/containerd/certs.d/"
  root_cert_path         = "${var.certs_path}/rootCA.pem"
}

# resource "local_file" "custom_resolv_conf" {
#   content = <<-CONF
#     nameserver 10.96.0.10
#     nameserver 172.18.0.1
#     # options edns0 ndots:0
#     search local-cluster.dev svc.cluster.local cluster.local
#     options ndots:5
#   CONF
#   filename = "${path.module}/custom_resolv.conf"
# }

resource "kind_cluster" "default" {
  name            = var.k8s_cluster_name
  kubeconfig_path = var.k8s_config_path
  node_image      = "kindest/node:${var.k8s_version}"
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    containerd_config_patches = [
      <<-TOML
        [plugins."io.containerd.grpc.v1.cri".registry]
          config_path = "${local.containerd_config_path}"
      TOML
    ]

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        <<-EOF
        kind: InitConfiguration
        nodeRegistration:
        kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOF
      ]

      /* Port mappings are not necessary because we have an actual LoadBalancer
      with an external IP.   This is only necessary if you need to expose host
      ports directly and have them forwarded to the cluster
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
      */
      /* Mount the self-signed cert into the node so it can communicate with
      ingresses */
      # extra_mounts {
      #   host_path      = local.root_cert_path
      #   container_path = "${local.containerd_config_path}/trow.${var.base_domain}/ca.crt"
      # }
      extra_mounts {
        host_path      = local.root_cert_path
        container_path = "${local.containerd_config_path}/harbor.${var.base_domain}/ca.crt"
      }
      # extra_mounts {
      #   host_path      = local_file.custom_resolv_conf.filename
      #   container_path = "/etc/resolv.conf"
      # }

    }

    node {
      role = "worker"
      /* Mount the self-signed cert into the node so it can communicate with
      ingresses */
      # extra_mounts {
      #   host_path      = local.root_cert_path
      #   container_path = "${local.containerd_config_path}/trow.${var.base_domain}/ca.crt"
      # }
      extra_mounts {
        host_path      = local.root_cert_path
        container_path = "${local.containerd_config_path}/harbor.${var.base_domain}/ca.crt"
      }      
      # extra_mounts {
      #   host_path      = local_file.custom_resolv_conf.filename
      #   container_path = "/etc/resolv.conf"
      # }
    }

    node {
      role = "worker"
      /* Mount the self-signed cert into the node so it can communicate with
      ingresses */
      # extra_mounts {
      #   host_path      = local.root_cert_path
      #   container_path = "${local.containerd_config_path}/trow.${var.base_domain}/ca.crt"
      # }
      extra_mounts {
        host_path      = local.root_cert_path
        container_path = "${local.containerd_config_path}/harbor.${var.base_domain}/ca.crt"
      }
      # extra_mounts {
      #   host_path      = local_file.custom_resolv_conf.filename
      #   container_path = "/etc/resolv.conf"
      # }
    }

    networking {
      disable_default_cni = var.use_cilium
    }
  }
  # depends_on = [local_file.custom_resolv_conf]
}

resource "kubectl_manifest" "additional_namespaces" {
  for_each  = toset(var.namespaces)
  yaml_body = <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${each.value}
YAML
  depends_on = [
    kind_cluster.default,
  ]
}