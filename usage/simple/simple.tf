module "nvidia_network_operator" {
  source = "../../module"

  namespace    = "network-operator"
  helm_version = "v26.4.2"
  nfd_enabled  = true
}
