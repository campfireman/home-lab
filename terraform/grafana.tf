locals {
  grafana_name = "grafana"
  grafana_port = 3000
}

resource "kubernetes_namespace" "grafana" {
  metadata {
    name = local.grafana_name
  }
}

resource "kubernetes_persistent_volume_claim" "grafana-pvc" {
  metadata {
    name      = "${local.grafana_name}-pvc"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = local.grafana_name
    namespace = kubernetes_namespace.grafana.metadata[0].name
    labels = {
      app = local.grafana_name
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.grafana_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.grafana_name
        }
      }

      spec {
        security_context {
          fs_group = 472
        }

        container {
          name              = local.grafana_name
          image             = "grafana/grafana:10.0.1"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.grafana_port
          }

          readiness_probe {
            http_get {
              path = "/robots.txt"
              port = local.grafana_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 2
          }

          liveness_probe {
            tcp_socket {
              port = local.grafana_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 30
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }

          volume_mount {
            name       = "${local.grafana_name}-pv"
            mount_path = "/var/lib/grafana"
          }
        }

        volume {
          name = "${local.grafana_name}-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana-pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana-service" {
  metadata {
    name      = "${local.grafana_name}-service"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  spec {
    selector = {
      app = local.grafana_name
    }
    port {
      port        = 80
      name        = "http"
      protocol    = "TCP"
      target_port = local.grafana_port
    }
  }
}

module "grafana_ingress" {
  source = "./modules/ingress"

  name            = "${local.grafana_name}-ingress"
  namespace       = kubernetes_namespace.grafana.metadata.0.name
  host            = "${local.grafana_name}.${local.new_domain}"
  service_name    = kubernetes_service.grafana-service.metadata[0].name
  service_port    = kubernetes_service.grafana-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.grafana_name}-tls"
}
