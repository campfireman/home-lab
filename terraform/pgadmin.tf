locals {
  pgadmin_name = "pgadmin"
}

resource "kubernetes_namespace" "pgadmin" {
  metadata {
    name = "pgadmin"
  }
}

resource "kubernetes_secret" "pgadmin_secrets" {
  metadata {
    name      = "pgadmin-secrets"
    namespace = kubernetes_namespace.pgadmin.metadata[0].name
  }

  type = "Opaque"

  data = {
    "pgadmin_password" = data.sops_file.secrets.data["pgadmin_password"]
  }
}

resource "kubernetes_config_map" "pgadmin_config" {
  metadata {
    name      = "pgadmin-config"
    namespace = kubernetes_namespace.pgadmin.metadata[0].name
  }

  data = {
    "servers.json" = jsonencode(
      {
        "Servers" : {
          "1" : {
            "Name" : "Shared Postgres DB",
            "Group" : "Servers",
            "Port" : 5432,
            "Username" : "${data.sops_file.secrets.data["postgres_shared_username"]}",
            "Host" : "postgres-service.postgres.svc.cluster.local",
            "SSLMode" : "prefer",
            "MaintenanceDB" : "postgres"
          }
        }
      }
    )
  }
}

resource "kubernetes_persistent_volume_claim" "pgadmin_pvc" {
  metadata {
    name      = "pgadmin-pvc"
    namespace = kubernetes_namespace.pgadmin.metadata[0].name
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

resource "kubernetes_deployment" "pgadmin" {
  metadata {
    name      = "pgadmin"
    namespace = kubernetes_namespace.pgadmin.metadata[0].name
    labels = {
      app = "pgadmin"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "pgadmin"
      }
    }

    template {
      metadata {
        labels = {
          app = "pgadmin"
        }
      }

      spec {
        termination_grace_period_seconds = 10
        security_context {
          run_as_user  = 0
          run_as_group = 0
        }

        container {
          name              = "pgadmin"
          image             = "dpage/pgadmin4:9.11.0"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "PGADMIN_DEFAULT_EMAIL"
            value = "admin@ture.dev"
          }

          env {
            name = "PGADMIN_DEFAULT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.pgadmin_secrets.metadata[0].name
                key  = "pgadmin_password"
              }
            }
          }

          port {
            name           = "http"
            container_port = 80
            protocol       = "TCP"
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          liveness_probe {
            tcp_socket {
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "750Mi"
            }
          }

          volume_mount {
            name       = "pgadmin-config"
            mount_path = "/pgadmin4/servers.json"
            sub_path   = "servers.json"
            read_only  = true
          }

          volume_mount {
            name       = "pgadmin-pv"
            mount_path = "/var/lib/pgadmin"
          }
        }

        volume {
          name = "pgadmin-config"
          config_map {
            name = kubernetes_config_map.pgadmin_config.metadata[0].name
          }
        }

        volume {
          name = "pgadmin-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.pgadmin_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "pgadmin_service" {
  metadata {
    name      = "pgadmin-service"
    namespace = kubernetes_namespace.pgadmin.metadata[0].name
  }
  spec {
    selector = {
      app = "pgadmin"
    }
    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }
  }
}

module "pgadmin_ingress" {
  source = "./modules/ingress"

  name            = "${local.pgadmin_name}-ingress"
  namespace       = kubernetes_namespace.pgadmin.metadata.0.name
  host            = "${local.pgadmin_name}.${local.domain}"
  service_name    = kubernetes_service.pgadmin_service.metadata[0].name
  service_port    = kubernetes_service.pgadmin_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.pgadmin_name}-tls"
  dns_target_ip   = local.master_node_ip
}
