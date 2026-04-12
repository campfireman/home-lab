locals {
  grampsweb_name = "grampsweb"
}

resource "kubernetes_namespace" "grampsweb" {
  metadata {
    name = "grampsweb"
  }
}

resource "kubernetes_persistent_volume_claim" "grampsweb_pvc" {
  metadata {
    name      = "grampsweb-pvc"
    namespace = kubernetes_namespace.grampsweb.metadata[0].name
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

resource "kubernetes_secret" "grampsweb_secrets" {
  metadata {
    name      = "grampsweb-secrets"
    namespace = kubernetes_namespace.grampsweb.metadata[0].name
  }

  type = "Opaque"

  data = {
    "gramps_secret_key" = data.sops_file.secrets.data["grampsweb_secret_key"]
  }
}

resource "kubernetes_service" "grampsweb_redis_service" {
  metadata {
    name      = "grampsweb-redis"
    namespace = kubernetes_namespace.grampsweb.metadata[0].name
  }
  spec {
    selector = {
      app = "grampsweb-redis"
    }
    port {
      port        = 6379
      target_port = 6379
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_deployment" "grampsweb_redis" {
  metadata {
    name      = "grampsweb-redis"
    namespace = kubernetes_namespace.grampsweb.metadata[0].name
    labels = {
      app = "grampsweb-redis"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grampsweb-redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "grampsweb-redis"
        }
      }

      spec {
        container {
          name              = "redis"
          image             = "docker.io/valkey/valkey:9.0.3-alpine"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 6379
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "grampsweb" {
  metadata {
    name      = "grampsweb"
    namespace = kubernetes_namespace.grampsweb.metadata[0].name
    labels = {
      app = "grampsweb"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grampsweb"
      }
    }

    template {
      metadata {
        labels = {
          app = "grampsweb"
        }
      }

      spec {
        termination_grace_period_seconds = 10

        # --- Container 1: Web App ---
        container {
          name              = "grampsweb"
          image             = "ghcr.io/gramps-project/grampsweb:26.4.1"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "GRAMPSWEB_TREE"
            value = "Gramps Web"
          }
          env {
            name  = "GRAMPSWEB_CELERY_CONFIG__broker_url"
            value = "redis://grampsweb-redis:6379/0"
          }
          env {
            name  = "GRAMPSWEB_CELERY_CONFIG__result_backend"
            value = "redis://grampsweb-redis:6379/0"
          }
          env {
            name  = "GRAMPSWEB_RATELIMIT_STORAGE_URI"
            value = "redis://grampsweb-redis:6379/1"
          }
          env {
            name = "GRAMPSWEB_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grampsweb_secrets.metadata[0].name
                key  = "gramps_secret_key"
              }
            }
          }

          port {
            name           = "http"
            container_port = 5000
            protocol       = "TCP"
          }

          readiness_probe {
            tcp_socket {
              port = 5000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          liveness_probe {
            tcp_socket {
              port = 5000
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
            name       = "grampsweb-pv"
            mount_path = "/app/users"
            sub_path   = "users"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/indexdir"
            sub_path   = "indexdir"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/thumbnail_cache"
            sub_path   = "thumbnail_cache"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/cache"
            sub_path   = "cache"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/secret"
            sub_path   = "secret"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/root/.gramps/grampsdb"
            sub_path   = "grampsdb"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/media"
            sub_path   = "media"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/tmp"
            sub_path   = "tmp"
          }
        }

        # --- Container 2: Celery Worker ---
        container {
          name              = "grampsweb-celery"
          image             = "ghcr.io/gramps-project/grampsweb:26.4.1"
          image_pull_policy = "IfNotPresent"
          command           = ["celery", "-A", "gramps_webapi.celery", "worker", "--loglevel=INFO", "--concurrency=2"]

          env {
            name  = "GRAMPSWEB_TREE"
            value = "Gramps Web"
          }
          env {
            name  = "GRAMPSWEB_CELERY_CONFIG__broker_url"
            value = "redis://grampsweb-redis:6379/0"
          }
          env {
            name  = "GRAMPSWEB_CELERY_CONFIG__result_backend"
            value = "redis://grampsweb-redis:6379/0"
          }
          env {
            name  = "GRAMPSWEB_RATELIMIT_STORAGE_URI"
            value = "redis://grampsweb-redis:6379/1"
          }
          env {
            name = "GRAMPSWEB_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grampsweb_secrets.metadata[0].name
                key  = "gramps_secret_key"
              }
            }
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "750Mi"
            }
          }

          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/users"
            sub_path   = "users"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/indexdir"
            sub_path   = "indexdir"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/thumbnail_cache"
            sub_path   = "thumbnail_cache"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/cache"
            sub_path   = "cache"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/secret"
            sub_path   = "secret"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/root/.gramps/grampsdb"
            sub_path   = "grampsdb"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/app/media"
            sub_path   = "media"
          }
          volume_mount {
            name       = "grampsweb-pv"
            mount_path = "/tmp"
            sub_path   = "tmp"
          }
        }

        volume {
          name = "grampsweb-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grampsweb_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grampsweb_service" {
  metadata {
    name      = "grampsweb-service"
    namespace = kubernetes_namespace.grampsweb.metadata[0].name
  }
  spec {
    selector = {
      app = "grampsweb"
    }
    port {
      port        = 80
      target_port = 5000
      protocol    = "TCP"
    }
  }
}

module "grampsweb_ingress" {
  source = "./modules/ingress"

  name            = "${local.grampsweb_name}-ingress"
  namespace       = kubernetes_namespace.grampsweb.metadata.0.name
  host            = "${local.grampsweb_name}.${local.domain}"
  service_name    = kubernetes_service.grampsweb_service.metadata[0].name
  service_port    = kubernetes_service.grampsweb_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.grampsweb_name}-tls"
  dns_target_ip   = local.master_node_ip
}
