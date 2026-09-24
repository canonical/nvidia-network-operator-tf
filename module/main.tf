terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/helm/latest/docs
provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

# ---------------
# Just to keep the YAML clean and avoid nulls
locals {
  inline_values = {
    nfd = {
      enabled = var.nfd_enabled
    }
    sriovNetworkOperator = {
      enabled = var.sriov_network_operator_enabled
    }
  }
}

resource "helm_release" "network_operator" {
  name             = "network-operator"
  repository       = "https://helm.ngc.nvidia.com/nvidia"
  chart            = "network-operator"
  create_namespace = true
  namespace        = var.namespace
  version          = var.helm_version

  # Pass inline YAML + optional file (if provided).
  # Helm merges `values` list entries in order, like multiple `-f` flags on
  # the CLI - the LAST entry wins on conflicts. The file is listed last so
  # it can override this module's own inputs, matching helm_config_file_path's
  # documented behavior.
  values = compact([
    yamlencode(local.inline_values),
    var.helm_config_file_path != null && var.helm_config_file_path != "" ? file(var.helm_config_file_path) : null,
  ])
}
