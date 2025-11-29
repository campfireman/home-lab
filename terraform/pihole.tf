locals {
  pihole_external_ip = "192.168.1.67"
  pihole_name        = "pi-hole"
  pihole_port        = 8080
}

resource "kubernetes_namespace" "pihole" {
  metadata {
    name = local.pihole_name
  }
}

resource "kubernetes_service" "pihole-service" {
  metadata {
    name      = "${local.pihole_name}-ext"
    namespace = kubernetes_namespace.pihole.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = local.pihole_port
      target_port = local.pihole_port
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_endpoints" "pihole" {
  metadata {
    name      = "${local.pihole_name}-ext"
    namespace = kubernetes_namespace.pihole.metadata[0].name
  }
  subset {
    address {
      ip = local.pihole_external_ip
    }
    port {
      name = "http"
      port = local.pihole_port
    }
  }
}

module "pihole_ingress" {
  source = "./modules/ingress"

  name            = "${local.pihole_name}-ingress"
  namespace       = kubernetes_namespace.pihole.metadata.0.name
  host            = "${local.pihole_name}.${local.domain}"
  service_name    = kubernetes_service.pihole-service.metadata[0].name
  service_port    = kubernetes_service.pihole-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.pihole_name}-tls"
  dns_target_ip   = local.master_node_ip
}
