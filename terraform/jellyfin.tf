locals {
  jellyfin_name = "jellyfin"
  jellyfin_port = 8096
}

resource "kubernetes_namespace" "jellyfin_namespace" {
  metadata {
    name = local.jellyfin_name
  }
}

resource "kubernetes_config_map" "jellyfin_config" {
  metadata {
    name      = "${local.jellyfin_name}-config"
    namespace = kubernetes_namespace.jellyfin_namespace.metadata.0.name
  }
  data = {
    TZ = "Europe/Berlin"
  }
}

resource "kubernetes_persistent_volume_claim" "jellyfin_config_pvc" {
  metadata {
    name      = "${local.jellyfin_name}-config-pvc"
    namespace = kubernetes_namespace.jellyfin_namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "jellyfin_deployment" {
  metadata {
    name      = "${local.jellyfin_name}-deployment"
    namespace = kubernetes_namespace.jellyfin_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.jellyfin_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.jellyfin_name
        }
      }
      spec {
        container {
          name              = "${local.jellyfin_name}-container"
          image             = "lscr.io/linuxserver/jellyfin:10.8.13-1-ls6"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.jellyfin_port
          }
          env_from {
            config_map_ref {
              name     = kubernetes_config_map.jellyfin_config.metadata.0.name
              optional = false
            }
          }

          security_context {
            privileged = true
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = local.jellyfin_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = local.jellyfin_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          volume_mount {
            name       = "zimaboard-nfs-media"
            mount_path = "/data"
            read_only  = true
          }
          volume_mount {
            name       = "${local.jellyfin_name}-config"
            mount_path = "/config"
            sub_path   = "${local.jellyfin_name}/config"
          }
        }
        volume {
          name = "${local.jellyfin_name}-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.jellyfin_config_pvc.metadata.0.name
          }
        }
        volume {
          name = "zimaboard-nfs-media"
          nfs {
            server    = "192.168.1.67"
            path      = "/var/nfs/media"
            read_only = true
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "jellyfin_service" {
  metadata {
    name      = "${local.jellyfin_name}-service"
    namespace = kubernetes_namespace.jellyfin_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.jellyfin_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.jellyfin_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_ingress_v1" "jellyfin_ingress" {
  metadata {
    name      = "${local.jellyfin_name}-ingress"
    namespace = kubernetes_namespace.jellyfin_namespace.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class" = "traefik"
      #   "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      #   "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }
  spec {
    rule {
      host = "${local.jellyfin_name}.${local.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.jellyfin_service.metadata.0.name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "${local.jellyfin_name}-tls"
      hosts       = ["${local.jellyfin_name}.${local.domain}"]
    }
  }
}
