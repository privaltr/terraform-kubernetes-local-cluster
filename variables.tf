variable "k8s_version" {
  description = "The version of kubernetes we'll make with kinds"
  type        = string
  default     = "v1.27.3"
}

variable "k8s_config_path" {
  description = "The location to put $KUBECONFIG."
  type        = string
}

variable "use_cilium" {
  description = "Decide if we want to use default CNI or replace with cilium"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD resources will be created"
  type        = string
  default     = "argocd"
}


variable "cert_manager_namespace" {
  description = "Namespace where cert-manager resources will be created"
  type        = string
  default     = "cert-manager"
}

variable "contour_namespace" {
  description = "Namespace where contour resources will be created"
  type        = string
  default     = "contour"
}

variable "cilium_namespace" {
  description = "Namespace where cilium resources will be created"
  type        = string
  default     = "cilium"
}

variable "trow_namespace" {
  description = "Namespace where trow resources will be created"
  type        = string
  default     = "trow"
}

variable "root_cert_name" {
  description = "The name of the root certificate secret"
  type        = string
  default     = "root-cert"
}

variable "base_domain" {
  description = "Base domain the ingress will be on"
  type        = string
}

variable "k8s_cluster_name" {
  description = "The name of the kind cluster"
  type        = string
}

variable "certs_path" {
  description = "The path where the root cert is at"
  type        = string
}

variable "enable_httpbin" {
  description = "Deploy httpbin into the cluster as a test application"
  type        = bool
  default     = false
}

variable "cidr_start" {
  description = "The start for the CIDR that is used for the loadbalancer"
  type        = number
  default     = 200
}

variable "cidr_end" {
  description = "The end for the CIDR that is used for the loadbalancer"
  type        = number
  default     = 210
}

variable "namespaces" {
  description = "The additional namespaces you want created"
  type        = list(string)
  default     = []
}

variable "additional_certs" {
  description = "The additional TLS certs you want created. Key is namespace, value is a list of DNS names"
  type        = map(list(string))
  default     = {}
}
variable "enable_vault" {
  description = "Deploy httpbin into the cluster as a test application"
  type        = bool
  default     = true
}

variable "vault_namespace" {
  description = "Namespace where Hashicorp resources will be created"
  type        = string
  default     = "vault"
}

variable "enable_k10" {
  description = "Deploy kasten k10 into the cluster as a test application"
  type        = bool
  default     = true
}

variable "k10_namespace" {
  description = "Namespace where Hashicorp resources will be created"
  type        = string
  default     = "kasten-k10"
}

variable "k10_admin_password" {
  description = "Admin password"
  type        = string
  default     = "test"
}
