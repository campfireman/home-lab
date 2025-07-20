locals {
  open_webui_name = "open-webui"
  open_webui_port = 8080
}

resource "kubernetes_namespace" "open_webui_namespace" {
  metadata {
    name = local.open_webui_name
  }
}

resource "kubernetes_persistent_volume_claim" "open_webui_pvc" {
  metadata {
    name      = "${local.open_webui_name}-pvc"
    namespace = kubernetes_namespace.open_webui_namespace.metadata.0.name
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

resource "kubernetes_deployment" "open_webui_deployment" {
  metadata {
    name      = "${local.open_webui_name}-deployment"
    namespace = kubernetes_namespace.open_webui_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.open_webui_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.open_webui_name
        }
      }
      spec {
        container {
          name              = "${local.open_webui_name}-container"
          image             = "ghcr.io/open-webui/open-webui:0.6.17"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.open_webui_port
          }

          env {
            name  = "OLLAMA_BASE_URL"
            value = "http://${module.ollama_ingress.ingress_host}"
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = local.open_webui_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = local.open_webui_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          volume_mount {
            name       = "${local.open_webui_name}-data"
            mount_path = "/app/backend/data"
            sub_path   = "data"
          }
        }
        volume {
          name = "${local.open_webui_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.open_webui_pvc.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "open_webui_service" {
  metadata {
    name      = "${local.open_webui_name}-service"
    namespace = kubernetes_namespace.open_webui_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.open_webui_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.open_webui_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "open_webui_ingress" {
  source = "./modules/ingress"

  name            = "${local.open_webui_name}-ingress"
  namespace       = kubernetes_namespace.open_webui_namespace.metadata.0.name
  host            = "${local.open_webui_name}.${local.domain}"
  service_name    = kubernetes_service.open_webui_service.metadata[0].name
  service_port    = kubernetes_service.open_webui_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.open_webui_name}-tls"
  dns_target_ip   = local.master_node_ip
}
