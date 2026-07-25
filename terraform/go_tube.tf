locals {
  go_tube_name = "go-tube"
  go_tube_port = 8080
}

resource "kubernetes_namespace" "go_tube_namespace" {
  metadata {
    name = local.go_tube_name
  }
}

resource "kubernetes_secret" "go_tube_secrets" {
  metadata {
    name      = "${local.go_tube_name}-secrets"
    namespace = kubernetes_namespace.go_tube_namespace.metadata.0.name
  }
  data = {
    MUSIC_PLAYLIST_URL = data.sops_file.secrets.data["gotube_music_playlist_url"]
    VIDEO_PLAYLIST_URL = data.sops_file.secrets.data["gotube_video_playlist_url"]
  }
}

resource "kubernetes_persistent_volume_claim" "go_tube_data_pvc" {
  metadata {
    name      = "${local.go_tube_name}-data-pvc"
    namespace = kubernetes_namespace.go_tube_namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "go_tube_deployment" {
  metadata {
    name      = "${local.go_tube_name}-deployment"
    namespace = kubernetes_namespace.go_tube_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        app = local.go_tube_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.go_tube_name
        }
      }
      spec {
        security_context {
          run_as_user     = 1000
          run_as_non_root = true
          fs_group        = 1000
        }
        container {
          name              = "${local.go_tube_name}-container"
          image             = "registry.home.arpa/go-tube:latest"
          image_pull_policy = "Always"
          port {
            container_port = local.go_tube_port
          }

          env_from {
            secret_ref {
              name     = kubernetes_secret.go_tube_secrets.metadata.0.name
              optional = false
            }
          }
          env {
            name  = "CANARY_VIDEO_ID"
            value = "dQw4w9WgXcQ"
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
          }

          liveness_probe {
            http_get {
              path   = "/healthz"
              port   = local.go_tube_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }
          readiness_probe {
            http_get {
              path   = "/readyz"
              port   = local.go_tube_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          volume_mount {
            name       = "youtube-music-nfs"
            mount_path = "/mnt/media/music"
          }
          volume_mount {
            name       = "youtube-video-nfs"
            mount_path = "/mnt/media/video"
          }
          volume_mount {
            name       = "${local.go_tube_name}-data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "scratch"
            mount_path = "/tmp/scratch"
          }
        }

        volume {
          name = "youtube-music-nfs"
          nfs {
            server = "192.168.1.67"
            path   = "/var/nfs/media/youtube/music"
          }
        }
        volume {
          name = "youtube-video-nfs"
          nfs {
            server = "192.168.1.67"
            path   = "/var/nfs/media/youtube/videos"
          }
        }
        volume {
          name = "${local.go_tube_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.go_tube_data_pvc.metadata.0.name
          }
        }
        volume {
          name = "scratch"
          empty_dir {
            size_limit = "32Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "go_tube_service" {
  metadata {
    name      = "${local.go_tube_name}-service"
    namespace = kubernetes_namespace.go_tube_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.go_tube_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.go_tube_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "go_tube_ingress" {
  source = "./modules/ingress"

  name            = "${local.go_tube_name}-ingress"
  namespace       = kubernetes_namespace.go_tube_namespace.metadata.0.name
  host            = "${local.go_tube_name}.${local.domain}"
  service_name    = kubernetes_service.go_tube_service.metadata[0].name
  service_port    = kubernetes_service.go_tube_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.go_tube_name}-tls"
  dns_target_ip   = local.master_node_ip
}
