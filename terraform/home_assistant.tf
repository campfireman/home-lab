locals {
  ha_external_ip = "192.168.1.67"
  ha_name        = "home-assistant"
  ha_port        = 8123
}

resource "kubernetes_namespace" "ha" {
  metadata {
    name = local.ha_name
  }
}

resource "kubernetes_service" "ha-service" {
  metadata {
    name      = "${local.ha_name}-ext"
    namespace = kubernetes_namespace.ha.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = local.ha_port
      target_port = local.ha_port
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_endpoints" "ha" {
  metadata {
    name      = "${local.ha_name}-ext"
    namespace = kubernetes_namespace.ha.metadata[0].name
  }
  subset {
    address {
      ip = local.ha_external_ip
    }
    port {
      name = "http"
      port = local.ha_port
    }
  }
}

module "ha_ingress" {
  source = "./modules/ingress"

  name            = "${local.ha_name}-ingress"
  namespace       = kubernetes_namespace.ha.metadata.0.name
  host            = "${local.ha_name}.${local.domain}"
  service_name    = kubernetes_service.ha-service.metadata[0].name
  service_port    = kubernetes_service.ha-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.ha_name}-tls"
  dns_target_ip   = local.master_node_ip
}
