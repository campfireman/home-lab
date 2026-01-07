locals {
  cookcli_name = "cookcli"
  cookcli_port = 9080
}

resource "kubernetes_namespace" "cookcli_namespace" {
  metadata {
    name = local.cookcli_name
  }
}
resource "kubernetes_secret" "cookcli_secrets" {
  metadata {
    name      = "${local.cookcli_name}-secrets"
    namespace = kubernetes_namespace.cookcli_namespace.metadata.0.name
  }

  data = {
    RCLONE_CONFIG_NC_TYPE = "webdav"
    RCLONE_CONFIG_NC_URL = data.sops_file.secrets.data["nextcloud_recipes_url"]
    RCLONE_CONFIG_NC_USER = data.sops_file.secrets.data["nextcloud_user"]
    RCLONE_CONFIG_NC_PASS = data.sops_file.secrets.data["nextcloud_password_rclone_obscured"]
  }
}

resource "kubernetes_persistent_volume_claim" "cookcli_pvc" {
  metadata {
    name      = "${local.cookcli_name}-pvc"
    namespace = kubernetes_namespace.cookcli_namespace.metadata.0.name
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

resource "kubernetes_deployment" "cookcli_deployment" {
  metadata {
    name      = "${local.cookcli_name}-deployment"
    namespace = kubernetes_namespace.cookcli_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.cookcli_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.cookcli_name
        }
      }
      spec {
        init_container {
          name  = "init-sync"
          image = "rclone/rclone:sha-3e111cb"
          env_from {
            secret_ref {
              name = "${local.cookcli_name}-secrets"
            }
          }
          command = ["rclone", "copy", "NC:", "/recipes", "--verbose"]
          volume_mount {
            name       = "data"
            mount_path = "/recipes"
            sub_path   = "recipes"
          }
        }

        container {
          name  = "server"
          image = "registry.home.arpa/cookcli:0.19.3"
          image_pull_policy = "Always"
          port {
            container_port = local.cookcli_port
          }
          volume_mount {
            name       = "data"
            mount_path = "/recipes"
            sub_path   = "recipes"
          }
        }

        container {
          name  = "sync"
          image = "rclone/rclone:sha-3e111cb"
          env_from {
            secret_ref {
              name = "${local.cookcli_name}-secrets"
            }
          }
          command = ["/bin/sh", "-c"]
          args = [
            "while true; do rclone sync NC: /recipes --verbose; sleep 300; done"
          ]
          volume_mount {
            name       = "data"
            mount_path = "/recipes"
            sub_path   = "recipes"
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.cookcli_pvc.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "cookcli_service" {
  metadata {
    name      = "${local.cookcli_name}-service"
    namespace = kubernetes_namespace.cookcli_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = local.cookcli_name
    }
    port {
      port        = 80
      target_port = local.cookcli_port
      name        = "http"
    }
  }
}

module "cookcli_ingress" {
  source = "./modules/ingress"

  name            = "${local.cookcli_name}-ingress"
  namespace       = kubernetes_namespace.cookcli_namespace.metadata.0.name
  host            = "${local.cookcli_name}.${local.domain}"
  service_name    = kubernetes_service.cookcli_service.metadata[0].name
  service_port    = kubernetes_service.cookcli_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.cookcli_name}-tls"
  dns_target_ip   = local.master_node_ip
}
