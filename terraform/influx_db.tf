locals {
  influx_db_name        = "influx-db"
  influx_db_config_path = "/conf/config.yaml"
  influx_db_http_port   = 8086
}

resource "kubernetes_namespace" "influx_db" {
  metadata {
    name = local.influx_db_name
  }
}

resource "kubernetes_persistent_volume_claim" "influx_db_pvc" {
  metadata {
    name      = "${local.influx_db_name}-pvc"
    namespace = kubernetes_namespace.influx_db.metadata.0.name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

resource "kubernetes_config_map" "influx_db_config" {
  metadata {
    name      = "${local.influx_db_name}-config"
    namespace = kubernetes_namespace.influx_db.metadata.0.name
  }
  data = {
    "config.yaml" = <<EOT
query-concurrency: 20
query-queue-size: 15
EOT
  }

}

resource "kubernetes_stateful_set" "influx_db_deployment" {
  metadata {
    name      = local.influx_db_name
    namespace = kubernetes_namespace.influx_db.metadata.0.name
    labels = {
      "app" = local.influx_db_name
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        "app" = local.influx_db_name
      }
    }
    service_name = "${local.influx_db_name}-deployment"
    template {
      metadata {
        labels = {
          "app" = local.influx_db_name
        }
      }
      spec {
        container {
          image = "influxdb:2.7.6"
          name  = local.influx_db_name
          port {
            container_port = local.influx_db_http_port
            name           = local.influx_db_name
          }
          env {
            name  = "INFLUXD_CONFIG_PATH"
            value = local.influx_db_config_path
          }
          volume_mount {
            name       = "${local.influx_db_name}-data"
            mount_path = "/var/lib/influxdb2"
            sub_path   = "data"
          }
          volume_mount {
            name       = "${local.influx_db_name}-conf"
            mount_path = local.influx_db_config_path
            sub_path   = "config.yaml"
          }
        }
        volume {
          name = "${local.influx_db_name}-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.influx_db_pvc.metadata.0.name
          }
        }
        volume {
          name = "${local.influx_db_name}-conf"
          config_map {
            name = kubernetes_config_map.influx_db_config.metadata.0.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "influx_db_service" {
  metadata {
    name      = "${local.influx_db_name}-service"
    namespace = kubernetes_namespace.influx_db.metadata.0.name
  }
  spec {
    type = "ClusterIP"
    selector = {
      app = kubernetes_stateful_set.influx_db_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      name        = "http"
      port        = 80
      target_port = local.influx_db_http_port
    }
  }
}

resource "kubernetes_ingress_v1" "influx_db_ingress" {
  metadata {
    name      = "${local.influx_db_name}-ingress"
    namespace = kubernetes_namespace.influx_db.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }
  spec {
    rule {
      host = "${local.influx_db_name}.${local.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.influx_db_service.metadata.0.name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "${local.influx_db_name}-tls"
      hosts       = ["${local.influx_db_name}.${local.domain}"]
    }
  }
}
