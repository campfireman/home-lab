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
          image             = "miniflux/miniflux:2.2.17"
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

module "miniflux_ingress" {
  source = "./modules/ingress"

  name            = "miniflux-ingress"
  namespace       = kubernetes_namespace.miniflux.metadata[0].name
  host            = "miniflux.${local.domain}"
  service_name    = kubernetes_service.miniflux_service.metadata[0].name
  service_port    = kubernetes_service.miniflux_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "miniflux-tls"
  dns_target_ip   = local.master_node_ip
}

resource "kubernetes_secret" "miniflux_cloudflared_token" {
  metadata {
    name      = "cloudflared-token"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
  }

  type = "Opaque"

  data = {
    "tunnel_token" = data.sops_file.secrets.data["cloudflare_tunnel_token_miniflux"]
  }
}

resource "kubernetes_deployment" "miniflux_cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.miniflux.metadata[0].name
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          
          args  = ["tunnel", "--metrics", "0.0.0.0:2000", "--no-autoupdate", "run",]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflared_token.metadata[0].name
                key  = "tunnel_token"
              }
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
          
          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}
