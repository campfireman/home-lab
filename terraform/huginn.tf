locals {
  huginn_name   = "huginn"
  huginn_port   = 3000
  huginn_digest = "1e0c359a46b1e84eb8c658404212eaf693b30e61"
}

resource "kubernetes_namespace" "huginn_namespace" {
  metadata {
    name = local.huginn_name
  }
}

resource "kubernetes_secret" "huginn_credentials" {
  metadata {
    name      = "${local.huginn_name}-secrets"
    namespace = kubernetes_namespace.huginn_namespace.metadata.0.name
  }
  type = "Opaque"

  data = {
    DATABASE_USERNAME = data.sops_file.secrets.data["postgres_shared_username"]
    DATABASE_PASSWORD = data.sops_file.secrets.data["postgres_shared_password"]
  }
}

resource "kubernetes_config_map" "huginn_config" {
  metadata {
    name      = "${local.huginn_name}-config"
    namespace = kubernetes_namespace.huginn_namespace.metadata.0.name
  }

  data = {
    DATABASE_ADAPTER = "postgresql"
    DATABASE_HOST    = "postgres-service.postgres.svc.cluster.local"
    DATABASE_PORT    = "5432"
    DATABASE_NAME    = "huginn"
    TIMEZONE         = "Europe/Berlin"
  }
}

resource "kubernetes_deployment" "huginn_deployment" {
  metadata {
    name      = "${local.huginn_name}-deployment"
    namespace = kubernetes_namespace.huginn_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.huginn_name
      }
    }
    template {
      metadata {
        labels = {
          app = local.huginn_name
        }
      }
      spec {
        container {
          name              = "${local.huginn_name}-container"
          image             = "ghcr.io/huginn/huginn-single-process:${local.huginn_digest}"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.huginn_port
          }

          env_from {
            secret_ref {
              name     = kubernetes_secret.huginn_credentials.metadata.0.name
              optional = false
            }
          }

          env_from {
            config_map_ref {
              name     = kubernetes_config_map.huginn_config.metadata.0.name
              optional = false
            }
          }

          liveness_probe {
            http_get {
              path   = "/"
              port   = local.huginn_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 15
          }
          readiness_probe {
            http_get {
              path   = "/"
              port   = local.huginn_port
              scheme = "HTTP"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "huginn_worker_deployment" {
  metadata {
    name      = "${local.huginn_name}-worker-deployment"
    namespace = kubernetes_namespace.huginn_namespace.metadata.0.name
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "${local.huginn_name}-worker"
      }
    }
    template {
      metadata {
        labels = {
          app = "${local.huginn_name}-worker"
        }
      }
      spec {
        container {
          name              = "${local.huginn_name}-worker-container"
          image             = "ghcr.io/huginn/huginn-single-process:${local.huginn_digest}"
          image_pull_policy = "IfNotPresent"

          command = ["/scripts/init", "bin/threaded.rb"]

          env_from {
            secret_ref {
              name     = kubernetes_secret.huginn_credentials.metadata.0.name
              optional = false
            }
          }

          env_from {
            config_map_ref {
              name     = kubernetes_config_map.huginn_config.metadata.0.name
              optional = false
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "huginn_service" {
  metadata {
    name      = "${local.huginn_name}-service"
    namespace = kubernetes_namespace.huginn_namespace.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment.huginn_deployment.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 80
      target_port = local.huginn_port
      name        = "http"
      protocol    = "TCP"
    }
  }
}

module "huginn_ingress" {
  source = "./modules/ingress"

  name            = "${local.huginn_name}-ingress"
  namespace       = kubernetes_namespace.huginn_namespace.metadata.0.name
  host            = "${local.huginn_name}.${local.domain}"
  service_name    = kubernetes_service.huginn_service.metadata[0].name
  service_port    = kubernetes_service.huginn_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.huginn_name}-tls"
}
