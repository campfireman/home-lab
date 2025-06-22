locals {
  rss_unlocker_name = "rss-unlocker"
  rss_unlocker_port = 8080
}

resource "kubernetes_namespace" "rss_unlocker_namespace" {
  metadata {
    name = local.rss_unlocker_name
  }
}

resource "kubernetes_deployment" "rss_unlocker_deployment" {
  metadata {
    name      = "${local.rss_unlocker_name}-deployment"
    namespace = kubernetes_namespace.rss_unlocker_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.rss_unlocker_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.rss_unlocker_name
        }
      }
      spec {
        container {
          name              = "${local.rss_unlocker_name}-container"
          image             = "registry.home.arpa/campfireman/rss-unlocker:1.0.0"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.rss_unlocker_port
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = local.rss_unlocker_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/health"
              port   = local.rss_unlocker_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "rss_unlocker_service" {
  metadata {
    name      = "${local.rss_unlocker_name}-service"
    namespace = kubernetes_namespace.rss_unlocker_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.rss_unlocker_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.rss_unlocker_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "rss_unlocker_ingress" {
  source = "./modules/ingress"

  name            = "${local.rss_unlocker_name}-ingress"
  namespace       = kubernetes_namespace.rss_unlocker_namespace.metadata.0.name
  host            = "${local.rss_unlocker_name}.${local.domain}"
  service_name    = kubernetes_service.rss_unlocker_service.metadata[0].name
  service_port    = kubernetes_service.rss_unlocker_service.spec[0].port[0].port
  tls_config      = "NO_TLS"
  tls_secret_name = "${local.rss_unlocker_name}-tls"
  dns_target_ip   = local.master_node_ip
}
