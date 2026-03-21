locals {
  postgres_name                  = "postgres"
  postgres_port                  = 5432
  postgres_shared_data_directory = "postgres_shared_database"
  postgres_version               = "18.3"
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
          image             = "postgres:${local.postgres_version}"
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

resource "kubernetes_cron_job_v1" "postgres_backup" {
  metadata {
    name      = "${local.postgres_name}-backup"
    namespace = kubernetes_namespace.postgres.metadata[0].name
  }

  spec {
    schedule = "0 0 * * *"
    job_template {
      metadata {
        name      = "${local.postgres_name}-backup"
        namespace = kubernetes_namespace.postgres.metadata[0].name
      }
      spec {
        template {
          metadata {
            name = "${local.postgres_name}-backup"
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = "${local.postgres_name}-backup"
              image = "postgres:${local.postgres_version}"

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

              env {
                name  = "PGPASSWORD"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.postgres_secrets.metadata.0.name
                    key  = "POSTGRES_PASSWORD"
                  }
                }
              }

              command = [
                "/bin/sh",
                "-c",
                <<-EOT
                set -e 
                FILE_NAME="/mnt/backup/backup-$(date +%Y-%m-%d-%H%M).sql.gz"
                
                echo "Starting backup..."
                pg_dumpall -h ${kubernetes_service.postgres_service.metadata.0.name} -U "$POSTGRES_USER" | gzip > "$FILE_NAME"
                
                echo "Cleaning up old backups (keeping 5)..."
                cd /mnt/backup && ls -t backup-*.sql.gz | tail -n +6 | xargs -r rm
                EOT
              ]

              volume_mount {
                name       = "zimaboard-nfs-postgres-backup"
                mount_path = "/mnt/backup"
              }
            }

            volume {
              name = "zimaboard-nfs-postgres-backup"
              nfs {
                server = "192.168.1.67"
                path   = "/var/nfs/backups/postgres"
              }
            }
          }
        }
      }
    }
  }
}
