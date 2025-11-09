locals {
  service_name = "mosquitto"
  port         = 1883
}

resource "kubernetes_namespace" "mosquitto_namespace" {
  metadata {
    name = local.service_name
  }
}

resource "kubernetes_persistent_volume_claim" "mosquitto_pvc" {
  metadata {
    name      = "${local.service_name}-pvc"
    namespace = kubernetes_namespace.mosquitto_namespace.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_config_map" "mosquitto_config" {
  metadata {
    name      = "${local.service_name}-config"
    namespace = kubernetes_namespace.mosquitto_namespace.metadata.0.name
  }
  data = {
    "mosquitto.conf" = <<EOT
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
listener 1883
protocol mqtt
require_certificate false
use_subject_as_username true
EOT
  }

}

resource "kubernetes_deployment" "mosquitto_deployment" {
  metadata {
    name      = "${local.service_name}-deployment"
    namespace = kubernetes_namespace.mosquitto_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.service_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.service_name
        }
      }
      spec {
        container {
          name              = "${local.service_name}-container"
          image             = "eclipse-mosquitto:2.0.22"
          image_pull_policy = "IfNotPresent"
          port {
            container_port = local.port
          }
          liveness_probe {
            tcp_socket {
              port = local.port
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            tcp_socket {
              port = local.port
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          volume_mount {
            name       = "mosquitto-conf"
            mount_path = "/mosquitto/config/mosquitto.conf"
            sub_path   = "mosquitto.conf"
            read_only  = true
          }
          volume_mount {
            name       = "mosquitto-data"
            mount_path = "/mosquitto/data"
            sub_path   = "mosquitto/data"
          }
        }
        volume {
          name = "${local.service_name}-conf"
          config_map {
            name = kubernetes_config_map.mosquitto_config.metadata.0.name
          }
        }
        volume {
          name = "${local.service_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mosquitto_pvc.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "mosquitto_service" {
  metadata {
    name      = "${local.service_name}-service"
    namespace = kubernetes_namespace.mosquitto_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.mosquitto_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 1883
      target_port = 1883
      name        = "mqtt"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_manifest" "ingressroutetcp_mosquitto_ingress" {
  manifest = {
    "apiVersion" = "traefik.io/v1alpha1"
    "kind"       = "IngressRouteTCP"
    "metadata" = {
      "name"      = "${local.service_name}-ingress"
      "namespace" = kubernetes_namespace.mosquitto_namespace.metadata.0.name
    }
    "spec" = {
      "entryPoints" = [
        "mqtt",
      ]
      "routes" = [
        {
          "match" = "HostSNI(`*`)"
          "services" = [
            {
              "name" = kubernetes_service.mosquitto_service.metadata.0.name
              "port" = local.port
            },
          ]
        },
      ]
    }
  }
}
