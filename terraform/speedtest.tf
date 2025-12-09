locals {
  speedtest_name = "speedtest"
}

resource "kubernetes_namespace" "speedtest" {
    metadata {
      name = "speedtest"
    }
}

resource "kubernetes_deployment" "speedtest_exporter" {
  metadata {
    name      = local.speedtest_name
    namespace = kubernetes_namespace.speedtest.metadata[0].name
    labels = {
      app = local.speedtest_name
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.speedtest_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.speedtest_name
        }
      }

      spec {
        container {
          name              = "speedtest"
          image             = "billimek/prometheus-speedtest-exporter:latest"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = 9469
            name           = "metrics"
          }

          resources {
            limits = {
              memory = "256Mi"
              cpu    = "500m"
            }
            requests = {
              memory = "128Mi"
              cpu    = "100m"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "speedtest_exporter" {
  metadata {
    name      = local.speedtest_name
    namespace = kubernetes_namespace.speedtest.metadata[0].name
    labels = {
      app     = local.speedtest_name
    }
  }

  spec {
    selector = {
      app = local.speedtest_name
    }
    port {
      port        = 9469
      target_port = 9469
      name        = "http-metrics"
    }
  }
}
