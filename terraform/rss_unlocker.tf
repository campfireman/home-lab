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
          image             = "registry.local/campfireman/rss-unlocker:1.0.0"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.rss_unlocker_port
          }

          security_context {
            privileged = true
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

resource "kubernetes_ingress_v1" "rss_unlocker_ingress" {
  metadata {
    name      = "${local.rss_unlocker_name}-ingress"
    namespace = kubernetes_namespace.rss_unlocker_namespace.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
      #   "cert-manager.io/cluster-issuer" = "internal-issuer"
      #   "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }
  spec {
    rule {
      host = "${local.rss_unlocker_name}.${local.new_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.rss_unlocker_service.metadata.0.name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "${local.rss_unlocker_name}-tls"
      hosts       = ["${local.rss_unlocker_name}.${local.new_domain}"]
    }
  }
}
