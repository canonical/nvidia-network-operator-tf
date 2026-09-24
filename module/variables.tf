variable "kubeconfig_path" {
  description = "Path to the kubeconfig of the existing k8s cluster to deploy onto."
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "The Kubernetes namespace to install the Network Operator in."
  type        = string
  default     = "network-operator"
}

variable "helm_version" {
  description = <<EOT
The version of the Network Operator Helm chart to deploy.
NOTE: Not all Network Operator releases have a Helm chart available.
Check with:

$ helm search repo nvidia/network-operator --versions
EOT

  type    = string
  default = "v26.4.2"
}

variable "nfd_enabled" {
  description = <<EOT
Whether to deploy the operator's bundled Node Feature Discovery (NFD).
Disable when NFD is already deployed by something else in the cluster (e.g.
the NVIDIA GPU Operator), to avoid two NFD master/worker sets fighting over
the same NodeFeatureRule CRDs.
EOT

  type    = bool
  default = true
}

variable "sriov_network_operator_enabled" {
  description = "Whether to deploy the SR-IOV Network Operator subsystem."
  type        = bool
  default     = false
}

variable "helm_config_file_path" {
  description = <<EOT
Path to a Helm values YAML file for additional configuration.

When this file is provided, its values will be merged with the chart's
defaults and this module's own inputs (nfd_enabled,
sriov_network_operator_enabled). Values set in this file take priority over
this module's inputs - see main.tf for why.
EOT

  type    = string
  default = null
}
