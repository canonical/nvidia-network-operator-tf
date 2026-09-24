module "nvidia_network_operator" {
  source = "../../module"

  nfd_enabled           = true # overridden to false by values.yaml below - file wins
  helm_config_file_path = "values.yaml"
}
