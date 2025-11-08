locals {
  prometheus_name = "prometheus"
  prometheus_port = 9090
}

resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = local.prometheus_name
  }
}

resource "kubernetes_config_map" "prometheus_server_conf" {
  metadata {
    name      = "prometheus-server-conf"
    namespace = "prometheus"
  }

  data = {
    "prometheus.yml" = <<EOF
global:
    scrape_interval: 15s
    evaluation_interval: 15s
scrape_configs:
    - job_name: 'prometheus'
      static_configs:
        - targets: ['localhost:9090']
    - job_name: 'zimaboard-smartctl'
      static_configs:
        - targets: ['192.168.1.67:9633']
EOF
  }
}

resource "kubernetes_persistent_volume_claim" "prometheus-pvc" {
  metadata {
    name      = "${local.prometheus_name}-pvc"
    namespace = kubernetes_namespace.prometheus.metadata[0].name
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

resource "kubernetes_deployment" "prometheus" {
  metadata {
    name      = local.prometheus_name
    namespace = kubernetes_namespace.prometheus.metadata[0].name
    labels = {
      app = local.prometheus_name
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.prometheus_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.prometheus_name
        }
      }

      spec {
        security_context {
          fs_group = 472
        }

        container {
          name              = local.prometheus_name
          image             = "prom/prometheus:v3.7.3"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.prometheus_port
          }

          readiness_probe {
            http_get {
              path = "/"
              port = local.prometheus_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 2
          }

          liveness_probe {
            tcp_socket {
              port = local.prometheus_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 30
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }

          volume_mount {
            name       = "${local.prometheus_name}-config"
            mount_path = "/etc/prometheus"
          }
          volume_mount {
            name       = "${local.prometheus_name}-pv"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "${local.prometheus_name}-config"
          config_map {
            name = kubernetes_config_map.prometheus_server_conf.metadata[0].name
          }
        }
        volume {
          name = "${local.prometheus_name}-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prometheus-pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "prometheus-service" {
  metadata {
    name      = "${local.prometheus_name}-service"
    namespace = kubernetes_namespace.prometheus.metadata[0].name
  }
  spec {
    selector = {
      app = local.prometheus_name
    }
    port {
      port        = 80
      name        = "http"
      protocol    = "TCP"
      target_port = local.prometheus_port
    }
  }
}

module "prometheus_ingress" {
  source = "./modules/ingress"

  name            = "${local.prometheus_name}-ingress"
  namespace       = kubernetes_namespace.prometheus.metadata.0.name
  host            = "${local.prometheus_name}.${local.domain}"
  service_name    = kubernetes_service.prometheus-service.metadata[0].name
  service_port    = kubernetes_service.prometheus-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.prometheus_name}-tls"
  dns_target_ip   = local.master_node_ip
}

