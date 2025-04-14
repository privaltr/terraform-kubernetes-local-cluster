terraform {
  required_providers {
    kind = {
      # https://registry.terraform.io/providers/tehcyx/kind/latest/docs
      source  = "tehcyx/kind"
      version = "~> 0.8.0"
    }

    # https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }

    kubectl = {
      # Don't use gavinbunney, it is abandoned and has critical bugs. This
      # fork fixes it.   Critical issues:
      # https://github.com/gavinbunney/terraform-provider-kubectl/issues/270
      source  = "alekc/kubectl"
      version = ">= 2.1.3"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "2.17.0"
    }
  }
}
