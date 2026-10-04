locals {
  miniflux_database = "miniflux"
}

resource "kubernetes_namespace_v1" "miniflux" {
  metadata {
    name = "miniflux"
  }
}

resource "kubernetes_config_map_v1" "miniflux_config" {
  metadata {
    name      = "miniflux-config"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
    labels = {
      app = "miniflux"
    }
  }

  data = {
    RUN_MIGRATIONS                 = "1"
    CREATE_ADMIN                   = "1"
    ADMIN_USERNAME                 = "admin"
    FETCHER_ALLOW_PRIVATE_NETWORKS = "1"
  }
}

# The cluster's internal-issuer root CA (public certificate, no key). Miniflux
# needs it to verify INTERNAL_TLS hosts such as n8n when it sends webhooks.
# Same PEM as renovate_internal_ca in renovate.tf. Update both on CA rotation.
resource "kubernetes_config_map_v1" "miniflux_internal_ca" {
  metadata {
    name      = "miniflux-internal-ca"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
  }
  data = {
    "internal-ca.pem" = <<-EOT
      -----BEGIN CERTIFICATE-----
      MIICjDCCAhKgAwIBAgIUJUMXJ4pmlhpSg/7GMkq0YoJr/AcwCgYIKoZIzj0EAwIw
      fTELMAkGA1UEBhMCREUxDDAKBgNVBAgMA0hBTTEMMAoGA1UEBwwDSEFNMQ4wDAYD
      VQQKDAV0X25ldDELMAkGA1UECwwCSVQxFjAUBgNVBAMMDVR1cmUgQ2xhdXNzZW4x
      HTAbBgkqhkiG9w0BCQEWDmFkbWluQHR1cmUuZGV2MB4XDTIzMDYyNzA4Mzc0N1oX
      DTMzMDYyNDA4Mzc0N1owfTELMAkGA1UEBhMCREUxDDAKBgNVBAgMA0hBTTEMMAoG
      A1UEBwwDSEFNMQ4wDAYDVQQKDAV0X25ldDELMAkGA1UECwwCSVQxFjAUBgNVBAMM
      DVR1cmUgQ2xhdXNzZW4xHTAbBgkqhkiG9w0BCQEWDmFkbWluQHR1cmUuZGV2MHYw
      EAYHKoZIzj0CAQYFK4EEACIDYgAElQTGRRskNUi+ojjJHCcmcFTN7zl1qqHsnIlI
      LDJJLK5kM9PJdZCe4Ebvtz6SKPj1WiPgJ6hWcPbOFJyokUpDHYb4HfHqrcGCD87q
      87CZnY1MUpFH1Cxy8fCpdj9Iern4o1MwUTAdBgNVHQ4EFgQU4ZIfpfVYB0DrWBPZ
      wBTTpxHvCaswHwYDVR0jBBgwFoAU4ZIfpfVYB0DrWBPZwBTTpxHvCaswDwYDVR0T
      AQH/BAUwAwEB/zAKBggqhkjOPQQDAgNoADBlAjEAp3N//h2LlYme1UL1sIaU2Lat
      6ArETULdXWIgzRlH/LK3+1tKovTeP7MfQ5Bel54HAjAcvwP88+mDnCqR1krpoysW
      S3k2AWMMEkk1Bdr7J2yEhXF1+7i5GUZS1vdIXj1NM4Y=
      -----END CERTIFICATE-----
    EOT
  }
}

resource "kubernetes_secret_v1" "miniflux_secrets" {
  metadata {
    name      = "miniflux-secrets"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
  }

  data = {
    DATABASE_URL   = "postgres://${data.sops_file.secrets.data["postgres_shared_username"]}:${data.sops_file.secrets.data["postgres_shared_password"]}@postgres-service.postgres.svc.cluster.local/${local.miniflux_database}?sslmode=disable"
    ADMIN_PASSWORD = data.sops_file.secrets.data["miniflux_admin_password"]
  }
}

resource "kubernetes_deployment_v1" "miniflux" {
  metadata {
    name      = "miniflux"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
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
          image             = "miniflux/miniflux:2.3.3"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 8080
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.miniflux_config.metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.miniflux_secrets.metadata[0].name
            }
          }

          env {
            name  = "SSL_CERT_FILE"
            value = "/etc/ssl/internal/internal-ca.pem"
          }

          volume_mount {
            name       = "internal-ca"
            mount_path = "/etc/ssl/internal"
            read_only  = true
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

        volume {
          name = "internal-ca"
          config_map {
            name = kubernetes_config_map_v1.miniflux_internal_ca.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "miniflux_service" {
  metadata {
    name      = "miniflux-service"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
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
  namespace       = kubernetes_namespace_v1.miniflux.metadata[0].name
  host            = "miniflux.${local.domain}"
  service_name    = kubernetes_service_v1.miniflux_service.metadata[0].name
  service_port    = kubernetes_service_v1.miniflux_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "miniflux-tls"
  dns_target_ip   = local.master_node_ip
}

resource "kubernetes_secret_v1" "miniflux_cloudflared_token" {
  metadata {
    name      = "cloudflared-token"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
  }

  type = "Opaque"

  data = {
    "tunnel_token" = data.sops_file.secrets.data["cloudflare_tunnel_token_miniflux"]
  }
}

resource "kubernetes_deployment_v1" "miniflux_cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace_v1.miniflux.metadata[0].name
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

          args = ["tunnel", "--metrics", "0.0.0.0:2000", "--no-autoupdate", "run", ]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.cloudflared_token.metadata[0].name
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
