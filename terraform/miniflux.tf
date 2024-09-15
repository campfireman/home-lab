locals {
  miniflux_database = "miniflux"
}

resource "kubernetes_namespace" "miniflux" {
  metadata {
    name = "miniflux"
  }
}

resource "kubernetes_config_map" "miniflux_config" {
  metadata {
    name      = "miniflux-config"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
    labels = {
      app = "miniflux"
    }
  }

  data = {
    RUN_MIGRATIONS = "1"
    CREATE_ADMIN   = "1"
    ADMIN_USERNAME = "admin"
  }
}

resource "kubernetes_secret" "miniflux_secrets" {
  metadata {
    name      = "miniflux-secrets"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
  }

  data = {
    DATABASE_URL   = "postgres://${data.sops_file.secrets.data["postgres_shared_username"]}:${data.sops_file.secrets.data["postgres_shared_password"]}@postgres-service.postgres.svc.cluster.local/${local.miniflux_database}?sslmode=disable"
    ADMIN_PASSWORD = data.sops_file.secrets.data["miniflux_admin_password"]
  }
}

resource "kubernetes_service" "miniflux_service" {
  metadata {
    name      = "miniflux-service"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
  }

  spec {
    selector = {
      app = "miniflux"
    }

    port {
      port        = 80
      name        = "http"
      protocol    = "TCP"
      target_port = 8080
    }
  }
}

resource "kubernetes_deployment" "miniflux" {
  metadata {
    name      = "miniflux"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
    labels = {
      app = "miniflux"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "miniflux"
      }
    }

    template {
      metadata {
        labels = {
          app = "miniflux"
        }
      }

      spec {
        container {
          name              = "miniflux"
          image             = "miniflux/miniflux:2.0.45"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 8080
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.miniflux_config.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.miniflux_secrets.metadata[0].name
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            failure_threshold     = 3
            success_threshold     = 1
            timeout_seconds       = 2
          }

          liveness_probe {
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
            success_threshold     = 1
            timeout_seconds       = 1
          }
        }
      }
    }
  }
}

# Ingress
resource "kubernetes_ingress_v1" "miniflux_ingress" {
  metadata {
    name      = "miniflux-ingress"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "miniflux.${local.new_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.miniflux_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["miniflux.${local.new_domain}"]
      secret_name = "miniflux-tls"
    }
  }
}
