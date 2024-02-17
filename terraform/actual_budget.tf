locals {
  actual_budget_name = "actual-budget"
  actual_budget_port = 5006
  config_path        = "/conf/config.json"
}

resource "kubernetes_namespace" "actual_budget_namespace" {
  metadata {
    name = local.actual_budget_name
  }
}

resource "kubernetes_persistent_volume_claim" "actual_budget_pvc" {
  metadata {
    name      = "${local.actual_budget_name}-pvc"
    namespace = kubernetes_namespace.actual_budget_namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

resource "kubernetes_config_map" "actual_budget_config" {
  metadata {
    name      = "${local.actual_budget_name}-config"
    namespace = kubernetes_namespace.actual_budget_namespace.metadata.0.name
  }
  data = {
    "config.json" = <<EOT
{
    "port": ${local.actual_budget_port}
}
EOT
  }

}

resource "kubernetes_deployment" "actual_budget_deployment" {
  metadata {
    name      = "${local.actual_budget_name}-deployment"
    namespace = kubernetes_namespace.actual_budget_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.actual_budget_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.actual_budget_name
        }
      }
      spec {
        container {
          name              = "${local.actual_budget_name}-container"
          image             = "docker.io/actualbudget/actual-server:24.2.0"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.actual_budget_port
          }
          env {
            name  = "ACTUAL_CONFIG_PATH"
            value = local.config_path
          }
          liveness_probe {
            http_get {
              path   = "/"
              port   = local.actual_budget_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = local.actual_budget_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          volume_mount {
            name       = "${local.actual_budget_name}-conf"
            mount_path = local.config_path
            sub_path   = "config.json"
            read_only  = true
          }
          volume_mount {
            name       = "${local.actual_budget_name}-data"
            mount_path = "/data"
            sub_path   = "${local.actual_budget_name}/data"
          }
        }
        volume {
          name = "${local.actual_budget_name}-conf"
          config_map {
            name = kubernetes_config_map.actual_budget_config.metadata.0.name
          }
        }
        volume {
          name = "${local.actual_budget_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.actual_budget_pvc.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "actual_budget_service" {
  metadata {
    name      = "${local.actual_budget_name}-service"
    namespace = kubernetes_namespace.actual_budget_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.actual_budget_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.actual_budget_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "actual_budget_ingress" {
  metadata {
    name      = "${local.actual_budget_name}-ingress"
    namespace = kubernetes_namespace.actual_budget_namespace.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }
  spec {
    rule {
      host = "${local.actual_budget_name}.${local.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.actual_budget_service.metadata.0.name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "${local.actual_budget_name}-tls"
      hosts       = ["${local.actual_budget_name}.${local.domain}"]
    }
  }
}
