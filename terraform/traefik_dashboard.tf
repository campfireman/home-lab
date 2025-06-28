locals {
  traefik_dashboard_name      = "traefik-dashboard"
  traefik_dashboard_namespace = "kube-system"
  traefik_dashboard_port      = 8080
}

resource "kubernetes_service" "traefik_dashboard_service" {
  metadata {
    name      = "${local.traefik_dashboard_name}-service"
    namespace = local.traefik_dashboard_namespace
    labels = {
      "app.kubernetes.io/instance" = "traefik"
      "app.kubernetes.io/name"     = local.traefik_dashboard_name
    }
  }
  spec {
    selector = {
      "app.kubernetes.io/instance" = "traefik-kube-system"
      "app.kubernetes.io/name"     = "traefik"
    }
    port {
      port        = 80
      target_port = local.traefik_dashboard_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "taefik_dashboard_ingress" {
  source = "./modules/ingress"

  name            = "${local.traefik_dashboard_name}-ingress"
  namespace       = local.traefik_dashboard_namespace
  host            = "${local.traefik_dashboard_name}.${local.domain}"
  service_name    = kubernetes_service.traefik_dashboard_service.metadata[0].name
  service_port    = kubernetes_service.traefik_dashboard_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = local.traefik_dashboard_name
  dns_target_ip   = local.master_node_ip
}
