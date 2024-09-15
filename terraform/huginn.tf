locals {
  huginn_name = "huginn"
  huginn_port = 3000
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
          image             = "ghcr.io/huginn/huginn-single-process:1066a61f06f640b12133767f2fb173201cc2ea24"
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
          image             = "ghcr.io/huginn/huginn-single-process:1066a61f06f640b12133767f2fb173201cc2ea24"
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

resource "kubernetes_ingress_v1" "huginn_ingress" {
  metadata {
    name      = "${local.huginn_name}-ingress"
    namespace = kubernetes_namespace.huginn_namespace.metadata.0.name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }
  spec {
    rule {
      host = "${local.huginn_name}.${local.new_domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.huginn_service.metadata.0.name
              port {
                name = "http"
              }
            }
          }
        }
      }
    }
    tls {
      secret_name = "${local.huginn_name}-tls"
      hosts       = ["${local.huginn_name}.${local.new_domain}"]
    }
  }
}
