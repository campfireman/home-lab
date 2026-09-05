locals {
  victorialogs_name = "victoria-logs"
  victorialogs_port = 9428
  fluentbit_name    = "fluent-bit"

  # -retention.maxDiskSpaceUsageBytes caps compressed on-disk data (parts +
  # indexdb), enforced at partition merge/rotation rather than continuously.
  # The PVC is sized above this so indexdb and in-flight merges have room
  # before old partitions get dropped.
  victorialogs_retention_bytes = 16 * 1024 * 1024 * 1024
}

resource "kubernetes_namespace_v1" "logging" {
  metadata {
    name = "logging"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "victorialogs-pvc" {
  metadata {
    name      = "${local.victorialogs_name}-pvc"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "victorialogs" {
  metadata {
    name      = local.victorialogs_name
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
    labels = {
      app = local.victorialogs_name
    }
  }

  spec {
    replicas = 1

    # Single replica on an RWO PVC: VictoriaLogs locks its storage data path,
    # so the default RollingUpdate (which starts the new pod before killing
    # the old one) would make the new pod fail to open storage while the old
    # one still holds it. Same reasoning as prometheus.tf.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = local.victorialogs_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.victorialogs_name
        }
      }

      spec {
        container {
          name              = local.victorialogs_name
          image             = "victoriametrics/victoria-logs:v1.52.0"
          image_pull_policy = "IfNotPresent"

          args = [
            "-storageDataPath=/victoria-logs-data",
            "-retentionPeriod=100y",
            "-retention.maxDiskSpaceUsageBytes=${local.victorialogs_retention_bytes}",
            "-httpListenAddr=:${local.victorialogs_port}",
          ]

          port {
            container_port = local.victorialogs_port
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = local.victorialogs_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 2
          }

          liveness_probe {
            tcp_socket {
              port = local.victorialogs_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 30
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }

          volume_mount {
            name       = "${local.victorialogs_name}-pv"
            mount_path = "/victoria-logs-data"
          }
        }

        volume {
          name = "${local.victorialogs_name}-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.victorialogs-pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "victorialogs-service" {
  metadata {
    name      = "${local.victorialogs_name}-service"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
  spec {
    selector = {
      app = local.victorialogs_name
    }
    port {
      port        = 80
      name        = "http"
      protocol    = "TCP"
      target_port = local.victorialogs_port
    }
  }
}

### --- Fluent Bit: collects container logs and ships them to VictoriaLogs --- ###

resource "kubernetes_service_account_v1" "fluentbit" {
  metadata {
    name      = local.fluentbit_name
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
}

resource "kubernetes_cluster_role_v1" "fluentbit" {
  metadata {
    name = local.fluentbit_name
  }

  # Read-only: Fluent Bit's kubernetes filter needs this to enrich log lines
  # with pod/namespace metadata.
  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "fluentbit" {
  metadata {
    name = local.fluentbit_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.fluentbit.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.fluentbit.metadata[0].name
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "fluentbit-config" {
  metadata {
    name      = "${local.fluentbit_name}-config"
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
  }

  data = {
    "fluent-bit.conf" = <<EOF
[SERVICE]
    Flush        5
    Daemon       Off
    Log_Level    info
    Parsers_File parsers.conf

[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Parser            cri
    Tag               kube.*
    Refresh_Interval  5
    Mem_Buf_Limit     64MB
    Skip_Long_Lines   On

[FILTER]
    Name                kubernetes
    Match               kube.*
    Kube_URL            https://kubernetes.default.svc:443
    Merge_Log           On

[OUTPUT]
    Name              http
    Match             *
    Host              ${kubernetes_service_v1.victorialogs-service.metadata[0].name}.${kubernetes_namespace_v1.logging.metadata[0].name}.svc.cluster.local
    Port              80
    URI               /insert/jsonline?_stream_fields=stream,kubernetes.namespace_name,kubernetes.pod_name&_msg_field=log&_time_field=date
    Format            json_lines
    json_date_key     date
    json_date_format  iso8601
    Compress          gzip
EOF

    "parsers.conf" = <<EOF
[PARSER]
    Name        cri
    Format      regex
    Regex       ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<log>.*)$
    Time_Key    time
    Time_Format %Y-%m-%dT%H:%M:%S.%L%z
EOF
  }
}

resource "kubernetes_daemon_set_v1" "fluentbit" {
  metadata {
    name      = local.fluentbit_name
    namespace = kubernetes_namespace_v1.logging.metadata[0].name
    labels = {
      app = local.fluentbit_name
    }
  }

  spec {
    selector {
      match_labels = {
        app = local.fluentbit_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.fluentbit_name
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.fluentbit.metadata[0].name

        container {
          name              = local.fluentbit_name
          image             = "fluent/fluent-bit:5.1.2"
          image_pull_policy = "IfNotPresent"

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }
          volume_mount {
            name       = "config"
            mount_path = "/fluent-bit/etc/"
          }
        }

        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.fluentbit-config.metadata[0].name
          }
        }
      }
    }
  }
}
