output "rdma_resource_name" {
  description = "The k8s extended resource name workloads should request to use InfiniBand, e.g. `rdma/<this value>: 1` in a pod spec."
  value       = "rdma/${var.rdma_resource_name}"
}

output "active_ifnames_configured" {
  description = "The full list of interface names the RDMA shared device plugin was configured to expose, flattened across all nodes in ib_topology."
  value       = local.all_active_ifnames
}
