#!/usr/bin/env bash
# Deploys one verify pod per node in a test pair, installs perftest inside
# the containers only (no host packages), runs a real ib_send_bw test
# across the InfiniBand fabric, and fails (non-zero exit) if the pods never
# get real RDMA devices or the measured bandwidth is below the threshold.
#
# This exists so `terraform apply` can prove "InfiniBand actually works
# between these nodes", not just "the operator/CR reports ready".
set -euo pipefail

kubeconfig="$1"
resource_name="$2"     # e.g. rdma_shared_device_ib (WITHOUT the rdma/ prefix)
server_node="$3"
client_node="$4"
min_bw_mbps="$5"       # 0 = skip the threshold check
keep_pods="$6"         # "true" or "false"
templates_dir="$7"

# Expand a leading "~" ourselves - this runs via Terraform's local-exec,
# not an interactive login shell, so the shell never gets a chance to
# expand it and KUBECONFIG=~/.kube/config would be taken literally.
kubeconfig="${kubeconfig/#\~/$HOME}"
export KUBECONFIG="$kubeconfig"
kctl() { kubectl "$@"; }

echo "==> Waiting for the RDMA shared device plugin daemonset to roll out..."
kctl rollout status daemonset/rdma-shared-dp-ds -n network-operator --timeout=180s

pair_id="${server_node}-${client_node}"
server_pod="ib-verify-server-${pair_id}"
client_pod="ib-verify-client-${pair_id}"

cleanup() {
  if [[ "$keep_pods" != "true" ]]; then
    kctl delete pod "$server_pod" "$client_pod" --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

render_pod() {
  local pod_name="$1" node_name="$2" role="$3"
  sed \
    -e "s/\${pod_name}/${pod_name}/g" \
    -e "s/\${node_name}/${node_name}/g" \
    -e "s/\${role}/${role}/g" \
    -e "s#\${resource_name_prefixed}#rdma/${resource_name}#g" \
    "${templates_dir}/verify-pod.yaml.tpl"
}

echo "==> Deploying verify pods: ${server_pod} (${server_node}), ${client_pod} (${client_node})"
render_pod "$server_pod" "$server_node" "server" | kctl apply -f -
render_pod "$client_pod" "$client_node" "client" | kctl apply -f -

echo "==> Waiting for pods to be Running..."
kctl wait --for=condition=Ready "pod/${server_pod}" --timeout=120s
kctl wait --for=condition=Ready "pod/${client_pod}" --timeout=120s

echo "==> Installing perftest inside the pods (container-scoped only, not on the hosts)..."
kctl exec "$server_pod" -- bash -c "apt-get update -qq && apt-get install -y -qq ibverbs-utils perftest >/tmp/install.log 2>&1"
kctl exec "$client_pod" -- bash -c "apt-get update -qq && apt-get install -y -qq ibverbs-utils perftest >/tmp/install.log 2>&1"

server_device=$(kctl exec "$server_pod" -- bash -c "ibv_devinfo | awk '/^hca_id:/{print \$2; exit}'")
client_device=$(kctl exec "$client_pod" -- bash -c "ibv_devinfo | awk '/^hca_id:/{print \$2; exit}'")
if [[ -z "$server_device" || -z "$client_device" ]]; then
  echo "FAIL: no RDMA device visible inside one or both pods (ibv_devinfo returned nothing)." >&2
  exit 1
fi
echo "==> server uses ${server_device}, client uses ${client_device}"

server_pod_ip=$(kctl get pod "$server_pod" -o jsonpath='{.status.podIP}')

echo "==> Starting ib_send_bw server..."
kctl exec "$server_pod" -- bash -c "nohup ib_send_bw -d ${server_device} > /tmp/server.log 2>&1 &"
sleep 2

echo "==> Running ib_send_bw client against ${server_pod_ip}..."
client_out=$(kctl exec "$client_pod" -- ib_send_bw -d "${client_device}" "${server_pod_ip}" 2>&1) || {
  echo "FAIL: ib_send_bw client run failed:" >&2
  echo "$client_out" >&2
  exit 1
}
echo "$client_out"

# Last "#bytes ... BW average[MB/sec] ..." data row, 4th field. The row is
# indented with leading whitespace, so match on that rather than "^[0-9]".
avg_bw=$(echo "$client_out" | awk '/^[[:space:]]*[0-9]+[[:space:]]/{line=$0} END{split(line,a," "); print a[4]}')
if [[ -z "$avg_bw" ]]; then
  echo "FAIL: could not parse average bandwidth from ib_send_bw output." >&2
  exit 1
fi

echo "==> Measured average bandwidth: ${avg_bw} MB/sec (threshold: ${min_bw_mbps} MB/sec)"
if (( $(echo "$min_bw_mbps > 0" | bc -l) )) && (( $(echo "$avg_bw < $min_bw_mbps" | bc -l) )); then
  echo "FAIL: measured bandwidth ${avg_bw} MB/sec is below the ${min_bw_mbps} MB/sec threshold." >&2
  exit 1
fi

echo "==> PASS: InfiniBand verified between ${server_node} and ${client_node} (${avg_bw} MB/sec)."
