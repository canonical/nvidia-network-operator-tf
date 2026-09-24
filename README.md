# Terraform NVIDIA Network Operator Module

This module deploys the NVIDIA Network Operator using its official Helm
chart. It provides a flexible way to install and configure the operator in
a Kubernetes cluster, so pods can request InfiniBand/RDMA and other
NVIDIA-networking resources.

Loosely follows the patterns of
[canonical/nvidia-gpu-operator-tf](https://github.com/canonical/nvidia-gpu-operator-tf),
adapted where the two operators' Helm charts genuinely differ (see
"Why this module stops at the Helm release" below).

# Features

Installs the NVIDIA Network Operator via the Helm provider. Configurable
namespace, chart version, bundled Node Feature Discovery (NFD), and SR-IOV
Network Operator subsystem. Supports an optional Helm values YAML file for
advanced configuration.

# Usage

To use this module, include it in your own Terraform configuration and
provide the necessary input variables. Examples under `usage/`:

```bash
cd usage/simple
terraform init
terraform apply
```

## Inputs

| Variable | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `kubeconfig_path` | Path to the kubeconfig of the existing k8s cluster to deploy onto. | string | `~/.kube/config` | no |
| `namespace` | Namespace to install the operator in. | string | `network-operator` | no |
| `helm_version` | Helm chart version to deploy. Check available versions with `helm search repo nvidia/network-operator --versions`. | string | `v26.4.2` | no |
| `nfd_enabled` | Deploy the operator's bundled Node Feature Discovery. Disable when NFD is already deployed by something else in the cluster (e.g. the GPU Operator), to avoid two NFD master/worker sets fighting over the same `NodeFeatureRule` CRDs. | bool | `true` | no |
| `sriov_network_operator_enabled` | Deploy the SR-IOV Network Operator subsystem. | bool | `false` | no |
| `helm_config_file_path` | Optional full Helm values YAML file. Merges with, and takes priority over, this module's own inputs. | string | `null` | no |

## Outputs

| Output | Description |
| --- | --- |
| `release_name` | The name of the Helm release. |
| `release_status` | The status of the Helm release. |
| `operator_version` | The configured version of the Network Operator. |
| `namespace` | The Kubernetes namespace the Network Operator (and its CRDs) were installed into. |

# Why this module stops at the Helm release

Unlike the GPU Operator's `ClusterPolicy` (fully templated from Helm
values), the Network Operator's chart does **not** render a
`NicClusterPolicy` CR from values - NVIDIA expects it applied as a separate
manifest. This isn't a shortcut here; it's how the upstream chart is
actually structured (checked directly against its `templates/` directory -
there is no `nicclusterpolicy.yaml` template).

That CR is also where all the *useful* behavior actually gets configured
(RDMA device plugin, OFED driver, IPoIB, secondary networks, etc.) - the
Helm release alone just gets you the controller, CRDs, and optionally NFD/
SR-IOV, sitting idle. This is the same pattern as e.g. `cert-manager`:
install the operator + CRDs first, then separately manage instances of its
CRs, because those are workload/cluster-specific configuration, not
"installation".

`NicClusterPolicy` also genuinely resists generalization: which interfaces
are safe to expose can't be reliably auto-detected (a physically-present IB
port can be uncabled/logically dead while looking identical to a live one
from PCI/vendor-ID metadata alone - see
`usage/with-nic-cluster-policy/README.md`), so the "topology" input is
inherently bespoke per cluster.

For these reasons, `NicClusterPolicy` is deliberately **not** wrapped by
this module. See `usage/with-nic-cluster-policy/` for a full worked example
(Helm release + CR + a real `ib_send_bw` verification step) to copy and
adapt - not a reusable module, on purpose.

If you're applying `NicClusterPolicy` from a separate Terraform root/state
than the one that installs this module (e.g. a downstream pipeline step
that runs after the operator, and its CRDs, already exist in the cluster),
you can use `kubernetes_manifest` directly with no chicken-and-egg problem
at all - the two-stage-apply workaround in the usage example is only needed
because that example applies both in one root, for the sake of being a
single, runnable demo.
