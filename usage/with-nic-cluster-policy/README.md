# Usage example: Network Operator + `NicClusterPolicy` + verification

**This is a worked reference, not a reusable module.** `NicClusterPolicy` is
deliberately *not* wrapped by `../../module` (see repo root `README.md`) -
it's a singleton, cluster-specific configuration object (much like the GPU
Operator's `ClusterPolicy`), and unlike `ClusterPolicy` it isn't rendered
from Helm values by the upstream chart, so there's nothing generic to wrap
without either guessing at your fabric's shape or exposing dozens of
rarely-agreed-upon spec fields. Copy this directory and adapt it.

## What it does

1. Installs the Network Operator via `../../module` (Helm).
2. Applies a `NicClusterPolicy` CR configuring the RDMA shared device
   plugin, so pods can request `rdma/<resource-name>: 1` and get a real IB
   device.
3. **Verifies it actually works**: deploys a throwaway pod pair (one per
   node in each configured `test_pairs` entry), runs `ib_send_bw` between
   them, and fails `terraform apply` if it can't get a real device or the
   measured bandwidth is below a configurable threshold.

## Why `ib_topology` is a required input, not auto-detected

A physical IB port can be:
- fully cabled, ACTIVE, with a subnet manager assigned (usable), or
- physically present, visible to `lspci`/vendor-ID selectors, but
  uncabled/logically DOWN with no subnet manager (**unusable**).

NVIDIA's own selector mechanism (`vendors`/`deviceIDs`/`linkTypes`) cannot
tell these apart - it matches on PCI metadata, which looks identical for a
cabled and an uncabled port of the same model. There is no way to
auto-discover "which ports are safe to expose" - a human has to check
`rdma link` (state == ACTIVE, `sm_lid` != 0) per node, once, and that's what
goes into `ib_topology`. Everything after that point (Helm install, CR
templating, pod verification) is fully automated.

## Two-stage apply required

`kubernetes_manifest.nic_cluster_policy`'s CRD comes from the same
`helm_release` that creates it (inside `../../module`), so the CRD doesn't
exist yet at first `plan`/`apply` time:

```bash
terraform init
terraform apply -target=module.network_operator -var-file=example.tfvars
terraform apply -var-file=example.tfvars
```

This is a known limitation of `hashicorp/kubernetes`'s `kubernetes_manifest`
(it validates against the CRD's OpenAPI schema at plan time). The
alternative is a community-maintained, non-hashicorp provider
(`alekc/kubectl`'s `kubectl_manifest`) that skips this validation and allows
a single-stage apply - deliberately not used here, to keep this repo's
provider footprint to just `helm` + `kubernetes`. If your own setup applies
`NicClusterPolicy` from a genuinely separate Terraform root/state (e.g. a
downstream pipeline unit that runs after the operator is already installed),
you don't hit this at all - see repo root `README.md`.

On success, `terraform apply` doesn't just report "resources created" - the
`null_resource.verify_ib` step will have actually run `ib_send_bw` between
your configured node pairs and printed the measured MB/sec, failing the
apply if it didn't clear `verify_min_bw_mbps`.

## Files

| File | Purpose |
|---|---|
| `variables.tf` | All inputs, incl. `ib_topology` (the topology object) and `verify_min_bw_mbps` |
| `main.tf` | Network Operator module call + `NicClusterPolicy` CR + verification, built from `ib_topology` |
| `scripts/run-ib-verify.sh` | Deploys pods, installs perftest *inside the containers only*, runs `ib_send_bw`, parses/checks bandwidth, cleans up |
| `templates/verify-pod.yaml.tpl` | Minimal pod manifest template requesting the RDMA resource |
| `outputs.tf` | Resource name to request in your own workloads, plus the resolved interface list |
| `example.tfvars` | A worked example topology with placeholder node/interface names - replace with your own |

## Known rough edges

- The two-stage-apply CRD/Helm chicken-and-egg problem above - not solved,
  just documented.
- `run-ib-verify.sh`'s bandwidth parsing assumes `ib_send_bw`'s default text
  output columns; a future perftest version changing its output format
  would need this adjusting.
- Doesn't handle the "plugin exposes 0 devices" failure modes (missing
  `ib_umad`/`rdma_cm`/`ib_ipoib` kernel modules, IPoIB netdev admin-down) -
  those are host-level prerequisites, arguably out of scope for this
  example and more of a "cluster readiness" precondition to check/automate
  separately.
