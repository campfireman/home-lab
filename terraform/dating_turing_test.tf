locals {
  dating_turing_test_name = "dating-turing-test"
}

resource "kubernetes_namespace" "dating_turing_test" {
  metadata {
    name = "dating-turing-test"
  }
}

resource "kubernetes_deployment" "dating-turing-test" {
  metadata {
    name      = "dating-turing-test"
    namespace = kubernetes_namespace.dating_turing_test.metadata[0].name
    labels = {
      app = "dating-turing-test"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "dating-turing-test"
      }
    }

    template {
      metadata {
        labels = {
          app = "dating-turing-test"
        }
      }

      spec {
        termination_grace_period_seconds = 10

        container {
          name              = "dating-turing-test"
          image             = "registry.home.arpa/campfireman/dating-turing-test:0.0.2"
          image_pull_policy = "IfNotPresent"


          port {
            name           = "http"
            container_port = 8080
            protocol       = "TCP"
          }

          readiness_probe {
            http_get {
              port = 8080
              path = "/"
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              port = 8080
              path = "/"
            }
            initial_delay_seconds = 5
            period_seconds        = 30
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "750Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "dating_turing_test_service" {
  metadata {
    name      = "dating-turing-test-service"
    namespace = kubernetes_namespace.dating_turing_test.metadata[0].name
  }
  spec {
    selector = {
      app = "dating-turing-test"
    }
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
  }
}

module "dating_turing_test_ingress" {
  source = "./modules/ingress"

  name            = "${local.dating_turing_test_name}-ingress"
  namespace       = kubernetes_namespace.dating_turing_test.metadata.0.name
  host            = "${local.dating_turing_test_name}.${local.domain}"
  service_name    = kubernetes_service.dating_turing_test_service.metadata[0].name
  service_port    = kubernetes_service.dating_turing_test_service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.dating_turing_test_name}-tls"
  dns_target_ip   = local.master_node_ip
}

resource "kubernetes_secret" "cloudflared_dating_turing_test_token" {
  metadata {
    name      = "cloudflared-token"
    namespace = kubernetes_namespace.dating_turing_test.metadata[0].name
  }

  type = "Opaque"

  data = {
    "tunnel_token" = data.sops_file.secrets.data["cloudflare_tunnel_token_dating_turing_test"]
  }
}

resource "kubernetes_deployment" "cloudflared_dating_turing_test" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.dating_turing_test.metadata[0].name
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          
          args  = ["tunnel", "--metrics", "0.0.0.0:2000", "--no-autoupdate", "run",]

          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.cloudflared_token.metadata[0].name
                key  = "tunnel_token"
              }
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
          
          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
      }
    }
  }
}
