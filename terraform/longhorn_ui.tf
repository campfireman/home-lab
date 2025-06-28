module "longhorn_ui_ingress" {
  source = "./modules/ingress"

  name            = "longhorn-ui-ingress"
  namespace       = "longhorn-system"
  host            = "longhorn-ui.${local.domain}"
  service_name    = "longhorn-frontend"
  service_port    = 80
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "longhorn-ui-tls"
  dns_target_ip   = local.master_node_ip
}
