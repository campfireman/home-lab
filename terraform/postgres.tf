locals {
  postgres_name                  = "postgres"
  postgres_port                  = 5432
  postgres_shared_data_directory = "postgres_shared_database"
}

resource "kubernetes_namespace" "postgres" {
  metadata {
    name = local.postgres_name
  }
}

resource "kubernetes_config_map" "postgres_config" {
  metadata {
    name      = "${local.postgres_name}-config"
    namespace = kubernetes_namespace.postgres.metadata.0.name
    labels = {
      app = local.postgres_name
    }
  }

  data = {
    POSTGRES_DB = local.postgres_shared_database
    PGDATA      = "${local.postgres_shared_data_directory}/pgdata"
  }
}

resource "kubernetes_secret" "postgres_secrets" {
  metadata {
    name      = "${local.postgres_name}-secrets"
    namespace = kubernetes_namespace.postgres.metadata.0.name
  }

  data = {
    POSTGRES_USER           = data.sops_file.secrets.data["postgres_shared_username"]
    POSTGRES_PASSWORD       = data.sops_file.secrets.data["postgres_shared_password"]
    POSTGRES_ADMIN_PASSWORD = data.sops_file.secrets.data["postgres_shared_admin_password"]
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "postgres_pvc" {
  metadata {
    name      = "${local.postgres_name}-pvc"
    namespace = kubernetes_namespace.postgres.metadata.0.name
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

resource "kubernetes_service" "postgres_service" {
  metadata {
    name      = "${local.postgres_name}-service"
    namespace = kubernetes_namespace.postgres.metadata.0.name
    labels = {
      app = local.postgres_name
    }
  }

  spec {
    type = "NodePort"
    selector = {
      app = local.postgres_name
    }
    port {
      port        = local.postgres_port
      target_port = local.postgres_port
    }
  }
}

resource "kubernetes_stateful_set" "postgres" {
  metadata {
    name      = local.postgres_name
    namespace = kubernetes_namespace.postgres.metadata.0.name
  }

  spec {
    service_name = local.postgres_name
    replicas     = 1

    selector {
      match_labels = {
        app = local.postgres_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.postgres_name
        }
      }

      spec {
        container {
          name              = local.postgres_name
          image             = "postgres:18.1"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.postgres_port
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.postgres_secrets.metadata.0.name
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.postgres_config.metadata.0.name
            }
          }

          volume_mount {
            name       = "postgres-pv"
            mount_path = local.postgres_shared_data_directory
          }
        }

        volume {
          name = "postgres-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.postgres_pvc.metadata.0.name
          }
        }
      }
    }
  }
}
