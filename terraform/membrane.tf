locals {
  membrane_name = "membrane"
  membrane_port = 8080
}

resource "kubernetes_namespace" "membrane_namespace" {
  metadata {
    name = local.membrane_name
  }
}

resource "kubernetes_deployment" "membrane_deployment" {
  metadata {
    name      = "${local.membrane_name}-deployment"
    namespace = kubernetes_namespace.membrane_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.membrane_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.membrane_name
        }
      }
      spec {
        container {
          name              = "${local.membrane_name}-container"
          image             = "registry.local/campfireman/membrane:0.0.1"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.membrane_port
          }

          liveness_probe {
            http_get {
              path   = "/health"
              port   = local.membrane_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/health"
              port   = local.membrane_port
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

resource "kubernetes_service" "membrane_service" {
  metadata {
    name      = "${local.membrane_name}-service"
    namespace = kubernetes_namespace.membrane_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.membrane_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.membrane_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "membrane_ingress" {
  metadata {
    name      = "${local.membrane_name}-ingress"
    namespace = kubernetes_namespace.membrane_namespace.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
      # "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      # "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }
  spec {
    rule {
      host = "${local.membrane_name}.${local.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.membrane_service.metadata.0.name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "${local.membrane_name}-tls"
      hosts       = ["${local.membrane_name}.${local.domain}"]
    }
  }
}
