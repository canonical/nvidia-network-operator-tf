terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
}

# https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

module "network_operator" {
  source = "../../module"

  kubeconfig_path = var.kubeconfig_path
  namespace       = var.namespace
  helm_version    = var.helm_version
  nfd_enabled     = var.nfd_enabled
}

locals {
  # Flatten every node's confirmed-active IB interface names into one list.
  # The RDMA shared device plugin's selector is cluster-wide (not templated
  # per node by the plugin itself) - it just ignores names it doesn't find
  # on a given node, so listing every node's active names together is safe
  # and is what lets one NicClusterPolicy serve a whole (possibly
  # heterogeneous) cluster.
  all_active_ifnames = distinct(flatten([
    for _, node in var.ib_topology.nodes : node.active_ifnames
  ]))
}

# Applied separately from the Helm release because this chart does not
# template a NicClusterPolicy CR from values - NVIDIA expects it to be
# applied as its own manifest. Must be named exactly "nic-cluster-policy"
# for the operator to act on it.
#
# IMPORTANT - two-stage apply required: this resource's CRD comes from the
# same helm_release that creates it (module.network_operator), so it does
# not exist yet at first `plan`/`apply` time. Run:
#
#   terraform apply -target=module.network_operator
#   terraform apply
#
# See README.md for why this can't be avoided without pulling in a
# non-hashicorp provider.
resource "kubernetes_manifest" "nic_cluster_policy" {
  # A one-off manual `kubectl patch` during live debugging can create a
  # competing field manager (easy to hit while iterating by hand);
  # force_conflicts keeps re-applies from failing once this file is the
  # source of truth.
  field_manager {
    force_conflicts = true
  }

  manifest = {
    apiVersion = "mellanox.com/v1alpha1"
    kind       = "NicClusterPolicy"
    metadata = {
      name = "nic-cluster-policy"
    }
    spec = merge(
      {
        rdmaSharedDevicePlugin = {
          image      = var.rdma_plugin_image.image
          repository = var.rdma_plugin_image.repository
          version    = var.rdma_plugin_image.version
          config = jsonencode({
            configList = [
              {
                resourceName = var.rdma_resource_name
                rdmaHcaMax   = var.rdma_hca_max
                selectors = {
                  # ifNames, NOT deviceIDs/vendors/linkTypes: those match
                  # every IB-capable port on a node including physically
                  # uncabled/no-subnet-manager ones. See README.md.
                  ifNames = local.all_active_ifnames
                }
              }
            ]
          })
        }
      },
      # ofedDriver block only included when explicitly requested - omitting
      # it entirely (rather than setting deploy=false) matches upstream's
      # own "don't touch driver" pattern for in-box-driver clusters.
      var.ofed_driver_enabled ? {
        ofedDriver = {
          deploy = true
        }
      } : {}
    )
  }

  depends_on = [module.network_operator]
}

# Runs a real ib_send_bw test between one pod per node, for every pair
# named in var.ib_topology.test_pairs. This is what turns "the operator
# reports ready" into "we actually measured RDMA throughput between these
# specific nodes" - the concrete proof point the whole exercise is for.
#
# Implemented as null_resource + local-exec (calling kubectl directly)
# rather than Terraform-native kubernetes_manifest/kubernetes_job, because
# this step needs interactive-ish behavior (wait, exec, install, exec
# again, parse output, decide pass/fail) that doesn't map cleanly onto a
# single declarative manifest.
resource "null_resource" "verify_ib" {
  for_each = {
    for pair in var.ib_topology.test_pairs :
    "${pair.server_node}-${pair.client_node}" => pair
  }

  triggers = {
    # Re-run verification whenever the CR config or the pair changes.
    nic_cluster_policy_selector = jsonencode(local.all_active_ifnames)
    server_node                 = each.value.server_node
    client_node                 = each.value.client_node
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/run-ib-verify.sh '${var.kubeconfig_path}' '${var.rdma_resource_name}' '${each.value.server_node}' '${each.value.client_node}' '${var.verify_min_bw_mbps}' '${var.keep_verification_pods}' '${path.module}/templates'"
  }

  depends_on = [kubernetes_manifest.nic_cluster_policy]
}
