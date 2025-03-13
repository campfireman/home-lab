resource "kubernetes_namespace" "recipes" {
  metadata {
    name = "recipes"
  }
}

resource "kubernetes_config_map" "recipes-nginx-config" {
  metadata {
    name      = "recipes-nginx-config"
    namespace = kubernetes_namespace.recipes.metadata[0].name
    labels = {
      app = "recipes"
    }
  }

  data = {
    "nginx-config" = <<-EOT
      events {
        worker_connections 1024;
      }
      http {
        include mime.types;
        server {
          listen 80;
          server_name _;

          client_max_body_size 16M;

          # serve static files
          location /static/ {
            alias /static/;
          }
          # serve media files
          location /media/ {
            alias /media/;
          }
        }
      }
    EOT
  }
}

resource "kubernetes_config_map" "recipes-env" {
  metadata {
    name      = "recipes-env"
    namespace = kubernetes_namespace.recipes.metadata[0].name
  }

  data = {
    DEBUG          = "0"
    ALLOWED_HOSTS  = "*"
    GUNICORN_MEDIA = "0"
    DB_ENGINE      = "django.db.backends.postgresql_psycopg2"
    POSTGRES_HOST  = "postgres-service.postgres.svc.cluster.local"
    POSTGRES_PORT  = "5432"
    POSTGRES_DB    = "recipes"
  }
}

resource "kubernetes_secret" "recipes" {
  metadata {
    name      = "recipes"
    namespace = kubernetes_namespace.recipes.metadata[0].name
  }

  type = "Opaque"

  data = {
    "SECRET_KEY"        = data.sops_file.secrets.data["tandoor_secret_key"]
    "POSTGRES_USER"     = data.sops_file.secrets.data["postgres_shared_username"]
    "POSTGRES_PASSWORD" = data.sops_file.secrets.data["postgres_shared_password"]
  }
}

resource "kubernetes_service_account" "recipes" {
  metadata {
    name      = "recipes"
    namespace = kubernetes_namespace.recipes.metadata[0].name
  }
}

resource "kubernetes_persistent_volume_claim" "recipes-media" {
  metadata {
    name      = "recipes-media"
    namespace = kubernetes_namespace.recipes.metadata[0].name
    labels = {
      app = "recipes"
    }
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

resource "kubernetes_persistent_volume_claim" "recipes-static" {
  metadata {
    name      = "recipes-static"
    namespace = kubernetes_namespace.recipes.metadata[0].name
    labels = {
      app = "recipes"
    }
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "recipes" {
  metadata {
    name      = "recipes"
    namespace = kubernetes_namespace.recipes.metadata[0].name
    labels = {
      app         = "recipes"
      environment = "production"
      tier        = "frontend"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app         = "recipes"
        environment = "production"
      }
    }

    template {
      metadata {
        labels = {
          app         = "recipes"
          tier        = "frontend"
          environment = "production"
        }
        annotations = {
          "backup.velero.io/backup-volumes" = "media,static"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.recipes.metadata[0].name

        init_container {
          name  = "init-chmod-data"
          image = "vabene1111/recipes:1.5.19"

          env_from {
            secret_ref {
              name = kubernetes_secret.recipes.metadata[0].name
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.recipes-env.metadata[0].name
            }
          }

          command = ["/bin/sh", "-c", <<-EOT
            set -e
            source venv/bin/activate
            echo "Updating database"
            python manage.py migrate
            python manage.py collectstatic_js_reverse
            python manage.py collectstatic --noinput
            echo "Setting media file attributes"
            chown -R 65534:65534 /opt/recipes/mediafiles
            find /opt/recipes/mediafiles -type d | xargs -r chmod 755
            find /opt/recipes/mediafiles -type f | xargs -r chmod 644
            echo "Done"
          EOT
          ]

          security_context {
            run_as_user                = 0
            allow_privilege_escalation = false
          }

          volume_mount {
            name       = "media"
            mount_path = "/opt/recipes/mediafiles"
            sub_path   = "files"
          }

          volume_mount {
            name       = "static"
            mount_path = "/opt/recipes/staticfiles"
            sub_path   = "files"
          }
        }

        container {
          name  = "recipes-nginx"
          image = "nginx:1.27.1"

          port {
            container_port = 80
            name           = "http"
          }

          port {
            container_port = 8080
            name           = "gunicorn"
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "64Mi"
            }
          }

          volume_mount {
            name       = "media"
            mount_path = "/media"
            sub_path   = "files"
          }

          volume_mount {
            name       = "static"
            mount_path = "/static"
            sub_path   = "files"
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx-config"
            read_only  = true
          }
        }

        container {
          name  = "recipes"
          image = "vabene1111/recipes:1.5.19"

          command = [
            "/opt/recipes/venv/bin/gunicorn",
            "-b", ":8080",
            "--access-logfile", "-",
            "--error-logfile", "-",
            "--log-level", "INFO",
            "recipes.wsgi"
          ]

          resources {
            requests = {
              cpu    = "250m"
              memory = "64Mi"
            }
          }

          liveness_probe {
            failure_threshold     = 3
            initial_delay_seconds = 0
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 1

            http_get {
              path   = "/"
              port   = "8080"
              scheme = "HTTP"
            }
          }

          readiness_probe {
            failure_threshold     = 3
            initial_delay_seconds = 0
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 1

            http_get {
              path   = "/"
              port   = "8080"
              scheme = "HTTP"
            }
          }


          volume_mount {
            name       = "media"
            mount_path = "/opt/recipes/mediafiles"
            sub_path   = "files"
          }

          volume_mount {
            name       = "static"
            mount_path = "/opt/recipes/staticfiles"
            sub_path   = "files"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.recipes.metadata[0].name
            }
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.recipes-env.metadata[0].name
            }
          }

          security_context {
            run_as_user = 65534
          }
        }

        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.recipes-media.metadata[0].name
          }
        }

        volume {
          name = "static"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.recipes-static.metadata[0].name
          }
        }

        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.recipes-nginx-config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "recipes-service" {
  metadata {
    name      = "recipes-service"
    namespace = kubernetes_namespace.recipes.metadata[0].name
    labels = {
      app  = "recipes"
      tier = "frontend"
    }
  }
  spec {
    selector = {
      app         = "recipes"
      tier        = "frontend"
      environment = "production"
    }
    port {
      port        = 80
      target_port = "http"
      name        = "http"
    }
    port {
      port        = 8080
      target_port = "gunicorn"
      name        = "gunicorn"
    }
  }
}

resource "kubernetes_ingress_v1" "recipes-ingress" {
  metadata {
    name      = "recipes-ingress"
    namespace = kubernetes_namespace.recipes.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "cert-manager.io/cluster-issuer"                   = "internal-issuer"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-redirect-https@kubernetescrd"
    }
  }

  spec {
    rule {
      host = "recipes.${local.domain}"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.recipes-service.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
        path {
          path      = "/media"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.recipes-service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
        path {
          path      = "/static"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.recipes-service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts       = ["recipes.${local.domain}"]
      secret_name = "recipes-tls"
    }
  }
}
