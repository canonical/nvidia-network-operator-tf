output "release_name" {
  description = "The name of the Helm release."
  value       = helm_release.network_operator.name
}

output "release_status" {
  description = "The status of the Helm release."
  value       = helm_release.network_operator.status
}

output "operator_version" {
  description = "The configured version of the Network Operator."
  value       = var.helm_version
}

output "namespace" {
  description = "The Kubernetes namespace the Network Operator (and its CRDs) were installed into."
  value       = helm_release.network_operator.namespace
}
