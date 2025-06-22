terraform {
  required_providers {
    pihole = {
      source  = "ryanwholey/pihole"
      version = "2.0.0-beta.1"
    }
  }
}

locals {
  base_annotations = {
    "kubernetes.io/ingress.class" = "traefik"
  }

  tls_annotations = {
    NO_TLS = {}
    INTERNAL_TLS = {
      "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
    PUBLIC_TLS = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }

  merged_annotations = merge(
    local.base_annotations,
    local.tls_annotations[var.tls_config],
    var.additional_annotations
  )
}

resource "kubernetes_ingress_v1" "ingress" {
  metadata {
    name        = var.name
    namespace   = var.namespace
    annotations = local.merged_annotations
  }

  spec {
    rule {
      host = var.host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = var.service_name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }

    dynamic "tls" {
      for_each = var.tls_config != "NO_TLS" ? [1] : []
      content {
        hosts       = [var.host]
        secret_name = var.tls_secret_name
      }
    }
  }
}

resource "pihole_dns_record" "record" {
  domain = var.host
  ip     = var.dns_target_ip
}
