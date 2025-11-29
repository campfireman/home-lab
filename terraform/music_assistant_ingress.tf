locals {
  ma_external_ip = "192.168.1.67"
  ma_name        = "music-assistant"
  ma_port        = 8095
}

resource "kubernetes_namespace" "ma" {
  metadata {
    name = local.ma_name
  }
}

resource "kubernetes_service" "ma-service" {
  metadata {
    name      = "${local.ma_name}-ext"
    namespace = kubernetes_namespace.ma.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = local.ma_port
      target_port = local.ma_port
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_endpoints_v1" "ma" {
  metadata {
    name      = "${local.ma_name}-ext"
    namespace = kubernetes_namespace.ma.metadata[0].name
  }
  subset {
    address {
      ip = local.ma_external_ip
    }
    port {
      name = "http"
      port = local.ma_port
    }
  }
}

module "ma_ingress" {
  source = "./modules/ingress"

  name            = "${local.ma_name}-ingress"
  namespace       = kubernetes_namespace.ma.metadata.0.name
  host            = "${local.ma_name}.${local.domain}"
  service_name    = kubernetes_service.ma-service.metadata[0].name
  service_port    = kubernetes_service.ma-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.ma_name}-tls"
  dns_target_ip   = local.master_node_ip
}
