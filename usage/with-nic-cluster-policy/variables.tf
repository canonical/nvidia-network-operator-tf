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
  description = "The version of the Network Operator Helm chart to deploy."
  type        = string
  default     = "v26.4.2"
}

variable "nfd_enabled" {
  description = "Whether to deploy the operator's bundled Node Feature Discovery (NFD)."
  type        = bool
  default     = true
}

variable "ofed_driver_enabled" {
  description = <<-EOT
    Whether to deploy NVIDIA's full DOCA-OFED driver container. Leave false
    when nodes already have a working in-box mlx5_core/ib_core driver with
    ACTIVE IB ports (verify with `rdma link` before choosing this) - this
    avoids replacing/reinstalling anything on the hosts.
  EOT
  type        = bool
  default     = false
}

variable "rdma_resource_name" {
  description = "Name of the k8s extended resource pods will request to use InfiniBand (e.g. rdma/<name>)."
  type        = string
  default     = "rdma_shared_device_ib"
}

variable "rdma_hca_max" {
  description = "Shared allocation slots per matched physical RDMA device (oversubscription factor, not a physical device count)."
  type        = number
  default     = 63
}

variable "rdma_plugin_image" {
  description = <<-EOT
    Public image for the RDMA shared device plugin. The upstream example CR
    defaults to NVIDIA's internal staging registry
    (nvcr.io/nvstaging/mellanox/...), which is NOT publicly pullable and
    causes ErrImagePull. Override with a public image/tag.
  EOT
  type = object({
    repository = string
    image      = string
    version    = string
  })
  default = {
    repository = "docker.io/mellanox"
    image      = "k8s-rdma-shared-dev-plugin"
    version    = "v1.3.2"
  }
}

# --- The topology input: this is the piece that MUST come from whoever is
# deploying this example. It cannot be auto-detected reliably, because a
# physically-present IB port can be uncabled/logically DOWN (no LID, no
# subnet manager) while still being fully visible to PCI/vendor/deviceID
# based discovery - see README.md for how the ifNames-only approach was
# arrived at.
variable "ib_topology" {
  description = <<-EOT
    Describes, per k8s node, which network interface names are CONFIRMED
    to be live, cabled, InfiniBand ports with an active subnet manager
    (i.e. `rdma link` shows state ACTIVE and a non-zero sm_lid). Only
    interfaces listed here are exposed to the RDMA shared device plugin via
    an `ifNames` selector - this is intentionally narrower than the
    vendor/deviceID selectors NVIDIA's own example CR uses, because those
    match dead ports too (see README.md "why ifNames, not deviceIDs").

    `test_pairs` is optional: each entry names two nodes that should be able
    to talk to each other over the fabric; the verification step will run a
    real ib_send_bw test between one pod per node in each pair and fail the
    apply if it doesn't get real throughput back.
  EOT
  type = object({
    nodes = map(object({
      # Kernel netdev names for this node's known-active IB ports, e.g.
      # ["ibs1f0", "ibs1f1"]. Discover with:
      #   rdma link                                   # find ACTIVE mlx5_N ports
      #   ip -br link | grep '^ib'                     # confirm/bring up netdev
      active_ifnames = list(string)
    }))
    test_pairs = optional(list(object({
      server_node = string
      client_node = string
    })), [])
  })

  validation {
    condition     = length(var.ib_topology.nodes) > 0
    error_message = "ib_topology.nodes must describe at least one node's active IB interfaces - this cannot be left empty or auto-detected."
  }
}

variable "verify_min_bw_mbps" {
  description = "Minimum acceptable ib_send_bw average bandwidth (MB/sec) for the verification step to pass. Set to 0 to skip the threshold check (still requires the test to run without error)."
  type        = number
  default     = 1000
}

variable "keep_verification_pods" {
  description = "If true, leave the verification pods running after apply (useful for further manual debugging). If false, they are deleted once the test completes."
  type        = bool
  default     = false
}
