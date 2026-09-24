# Example topology input. Replace the node names and interface names with
# your own cluster's - discover them per node with:
#
#   1. `rdma link`
#      Lists every RDMA device/port with its state.
#   2. For each ACTIVE port with a non-zero sm_lid, find its netdev name:
#        ip -br link | grep '^ib'
#      This may show DOWN/NO-CARRIER even for a genuinely active IB port if
#      nobody has ever `ip link set <dev> up`'d it - bring it up and
#      recheck LOWER_UP before trusting the result.
#   3. List ONLY the netdev names that came from an ACTIVE, sm_lid-assigned
#      port. Do NOT include ports that are physically present but
#      Down/Disabled/no-SM - see README.md for why this matters.

ib_topology = {
  nodes = {
    node-a = {
      active_ifnames = ["ibs1f0", "ibs1f1"]
    }
    node-b = {
      active_ifnames = ["ibp18s0"]
    }
  }

  test_pairs = [
    {
      server_node = "node-a"
      client_node = "node-b"
    }
  ]
}

verify_min_bw_mbps = 1000 # adjust to whatever your fabric/HCA generation can sustain
