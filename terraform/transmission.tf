locals {
  transmission_name = "transmission"
  transmission_port = 9091
}

resource "kubernetes_namespace" "transmission_namespace" {
  metadata {
    name = local.transmission_name
  }
}

resource "kubernetes_persistent_volume_claim" "transmission_config_pvc" {
  metadata {
    name      = "${local.transmission_name}-config-pvc"
    namespace = kubernetes_namespace.transmission_namespace.metadata.0.name
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

resource "kubernetes_config_map" "transmission_config" {
  metadata {
    name      = "${local.transmission_name}-config"
    namespace = kubernetes_namespace.transmission_namespace.metadata.0.name
  }
  data = {
    CONFIG_FILE              = "/wg-config/wg0.conf"
  }
}

resource "kubernetes_secret" "wireguard_config" {
  metadata {
    name      = "wireguard-manual-config"
    namespace = kubernetes_namespace.transmission_namespace.metadata.0.name
  }

  type = "Opaque"

  data = {
    "wg0.conf" = <<EOF
[Interface]
PrivateKey = ${data.sops_file.secrets.data["mullvad_private_key"]}
Address = 10.70.217.243/32,fc00:bbbb:bbbb:bb01::7:d9f2/128
DNS = 10.64.0.1

[Peer]
PublicKey = ${data.sops_file.secrets.data["mullvad_server_pubkey"]}
AllowedIPs = 0.0.0.0/0,::0/0
Endpoint = ${data.sops_file.secrets.data["mullvad_endpoint"]}
EOF
  }
}

resource "kubernetes_deployment" "transmission_deployment" {
  metadata {
    name      = "${local.transmission_name}-deployment"
    namespace = kubernetes_namespace.transmission_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.transmission_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.transmission_name
        }
      }
      spec {
        container {
          name              = "${local.transmission_name}-container"
          image             = "haugene/transmission-wireguard:main"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.transmission_port
          }
          env_from {
            config_map_ref {
              name     = kubernetes_config_map.transmission_config.metadata.0.name
              optional = false
            }
          }

          security_context {
            privileged = true
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = local.transmission_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 120
            period_seconds        = 20
          }

          readiness_probe {
            http_get {
              path   = "/"
              port   = local.transmission_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          volume_mount {
            name       = "zimaboard-nfs-media"
            mount_path = "/data"
          }
          volume_mount {
            name       = "${local.transmission_name}-config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "wireguard-conf-volume"
            mount_path = "/wg-config/wg0.conf"
            sub_path   = "wg0.conf"
            read_only  = true
          }
        }
        volume {
          name = "${local.transmission_name}-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.transmission_config_pvc.metadata.0.name
          }
        }
        volume {
          name = "wireguard-conf-volume"
          secret {
            secret_name = kubernetes_secret.wireguard_config.metadata.0.name
          }
        }
        volume {
          name = "zimaboard-nfs-media"
          nfs {
            server = "192.168.1.67"
            path   = "/var/nfs/media"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "transmission_service" {
  metadata {
    name      = "${local.transmission_name}-service"
    namespace = kubernetes_namespace.transmission_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.transmission_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.transmission_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "transmission_ingress" {
  source = "./modules/ingress"

  name            = "${local.transmission_name}-ingress"
  namespace       = kubernetes_namespace.transmission_namespace.metadata.0.name
  host            = "${local.transmission_name}.${local.domain}"
  service_name    = kubernetes_service.transmission_service.metadata[0].name
  service_port    = kubernetes_service.transmission_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.transmission_name}-tls"
  dns_target_ip   = local.master_node_ip
}
