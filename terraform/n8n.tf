locals {
  n8n_name = "n8n"
  n8n_port = 5678
}

resource "kubernetes_namespace_v1" "n8n" {
  metadata {
    name = local.n8n_name
  }
}

resource "kubernetes_persistent_volume_claim_v1" "n8n_pvc" {
  metadata {
    name      = "${local.n8n_name}-pvc"
    namespace = kubernetes_namespace_v1.n8n.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_secret_v1" "n8n_secrets" {
  metadata {
    name      = "${local.n8n_name}-secrets"
    namespace = kubernetes_namespace_v1.n8n.metadata[0].name
  }
  type = "Opaque"

  data = {
    N8N_ENCRYPTION_KEY     = data.sops_file.secrets.data["n8n_encryption_key"]
    DB_POSTGRESDB_USER     = data.sops_file.secrets.data["postgres_shared_username"]
    DB_POSTGRESDB_PASSWORD = data.sops_file.secrets.data["postgres_shared_password"]
  }
}

resource "kubernetes_config_map_v1" "n8n_config" {
  metadata {
    name      = "${local.n8n_name}-config"
    namespace = kubernetes_namespace_v1.n8n.metadata[0].name
  }

  data = {
    DB_TYPE                = "postgresdb"
    DB_POSTGRESDB_HOST     = "postgres-service.postgres.svc.cluster.local"
    DB_POSTGRESDB_PORT     = "5432"
    DB_POSTGRESDB_DATABASE = "n8n"
    N8N_HOST               = "${local.n8n_name}.${local.domain}"
    N8N_PORT               = tostring(local.n8n_port)
    N8N_PROTOCOL           = "https"
    WEBHOOK_URL            = "https://${local.n8n_name}.${local.domain}/"
    GENERIC_TIMEZONE       = "Europe/Berlin"
    N8N_RUNNERS_ENABLED    = "true"
  }
}

resource "kubernetes_deployment_v1" "n8n" {
  metadata {
    name      = local.n8n_name
    namespace = kubernetes_namespace_v1.n8n.metadata[0].name
    labels = {
      app = local.n8n_name
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.n8n_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.n8n_name
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }

        container {
          name              = local.n8n_name
          image             = "docker.io/n8nio/n8n:2.35.3"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.n8n_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.n8n_secrets.metadata[0].name
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.n8n_config.metadata[0].name
            }
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = local.n8n_port
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = local.n8n_port
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }

          volume_mount {
            name       = "n8n-pv"
            mount_path = "/home/node/.n8n"
          }
        }

        volume {
          name = "n8n-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.n8n_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "n8n_service" {
  metadata {
    name      = "${local.n8n_name}-service"
    namespace = kubernetes_namespace_v1.n8n.metadata[0].name
  }
  spec {
    selector = {
      app = local.n8n_name
    }
    port {
      port        = 80
      target_port = local.n8n_port
      protocol    = "TCP"
    }
  }
}

module "n8n_ingress" {
  source = "./modules/ingress"

  name            = "${local.n8n_name}-ingress"
  namespace       = kubernetes_namespace_v1.n8n.metadata[0].name
  host            = "${local.n8n_name}.${local.domain}"
  service_name    = kubernetes_service_v1.n8n_service.metadata[0].name
  service_port    = kubernetes_service_v1.n8n_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.n8n_name}-tls"
  dns_target_ip   = local.master_node_ip
}
