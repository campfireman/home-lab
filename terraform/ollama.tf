locals {
  ollama_name = "ollama"
  ollama_port = 11434
}

resource "kubernetes_namespace" "ollama_namespace" {
  metadata {
    name = local.ollama_name
  }
}

resource "kubernetes_persistent_volume_claim" "ollama_pvc" {
  metadata {
    name      = "${local.ollama_name}-pvc"
    namespace = kubernetes_namespace.ollama_namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "30Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "ollama_deployment" {
  metadata {
    name      = "${local.ollama_name}-deployment"
    namespace = kubernetes_namespace.ollama_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.ollama_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.ollama_name
        }
      }
      spec {
        container {
          name              = "${local.ollama_name}-container"
          image             = "ollama/ollama:0.5.7"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.ollama_port
          }

          #   resources {
          #     requests = {
          #       cpu    = "1000m"
          #       memory = "16Gi"
          #     }
          #   }

          lifecycle {
            post_start {
              exec {
                command = ["/bin/sh", "-c", "echo gemma2 deepseek-r1:7b | xargs -n1 /bin/ollama pull"]
              }
            }
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = local.ollama_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = local.ollama_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          volume_mount {
            name       = "${local.ollama_name}-data"
            mount_path = "/root/.ollama"
            sub_path   = "data"
          }
        }
        volume {
          name = "${local.ollama_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_pvc.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ollama_service" {
  metadata {
    name      = "${local.ollama_name}-service"
    namespace = kubernetes_namespace.ollama_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.ollama_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.ollama_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "ollama_ingress" {
  source = "./modules/ingress"

  name            = "${local.ollama_name}-ingress"
  namespace       = kubernetes_namespace.ollama_namespace.metadata.0.name
  host            = "${local.ollama_name}.${local.new_domain}"
  service_name    = kubernetes_service.ollama_service.metadata[0].name
  service_port    = kubernetes_service.ollama_service.spec[0].port[0].port
  tls_config      = "NO_TLS"
  tls_secret_name = "${local.ollama_name}-tls"
}
