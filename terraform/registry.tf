locals {
  registry_name = "registry"
  registry_port = 5000
}

resource "kubernetes_namespace" "registry_namespace" {
  metadata {
    name = local.registry_name
  }
}

resource "kubernetes_persistent_volume_claim" "registry_pvc" {
  metadata {
    name      = "${local.registry_name}-pvc"
    namespace = kubernetes_namespace.registry_namespace.metadata.0.name
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

resource "kubernetes_deployment" "registry_deployment" {
  metadata {
    name      = "${local.registry_name}-deployment"
    namespace = kubernetes_namespace.registry_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.registry_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.registry_name
        }
      }
      spec {
        container {
          name              = "${local.registry_name}-container"
          image             = "registry:3.0.0"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.registry_port
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = local.registry_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = local.registry_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          volume_mount {
            name       = "${local.registry_name}-data"
            mount_path = "/var/lib/registry"
            sub_path   = "data"
          }
        }
        volume {
          name = "${local.registry_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.registry_pvc.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "registry_service" {
  metadata {
    name      = "${local.registry_name}-service"
    namespace = kubernetes_namespace.registry_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.registry_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.registry_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "registry_ingress" {
  source = "./modules/ingress"

  name            = "${local.registry_name}-ingress"
  namespace       = kubernetes_namespace.registry_namespace.metadata.0.name
  host            = "${local.registry_name}.${local.domain}"
  service_name    = kubernetes_service.registry_service.metadata[0].name
  service_port    = kubernetes_service.registry_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.registry_name}-tls"
  dns_target_ip   = local.master_node_ip
}
