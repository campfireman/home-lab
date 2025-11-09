locals {
  grafana_name = "grafana"
  grafana_port = 3000
}

resource "kubernetes_namespace" "grafana" {
  metadata {
    name = local.grafana_name
  }
}

resource "kubernetes_persistent_volume_claim" "grafana-pvc" {
  metadata {
    name      = "${local.grafana_name}-pvc"
    namespace = kubernetes_namespace.grafana.metadata[0].name
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

resource "kubernetes_secret" "grafana_secrets" {
  metadata {
    name      = "grafana-secrets"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }

  data = {
    GF_ADMIN_USER     = data.sops_file.secrets.data["grafana_admin_user"]
    GF_ADMIN_PASSWORD = data.sops_file.secrets.data["grafana_admin_password"]
  }
}

resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = local.grafana_name
    namespace = kubernetes_namespace.grafana.metadata[0].name
    labels = {
      app = local.grafana_name
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.grafana_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.grafana_name
        }
      }

      spec {
        security_context {
          fs_group = 472
        }

        container {
          name              = local.grafana_name
          image             = "grafana/grafana:12.3.0-18925857539"
          image_pull_policy = "IfNotPresent"

          port {
            container_port = local.grafana_port
          }

          env {
            name = "GF_SECURITY_ADMIN_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_secrets.metadata[0].name
                key  = "GF_ADMIN_USER"
              }
            }
          }
          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_secrets.metadata[0].name
                key  = "GF_ADMIN_PASSWORD"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/robots.txt"
              port = local.grafana_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 10
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 2
          }

          liveness_probe {
            tcp_socket {
              port = local.grafana_port
            }
            failure_threshold     = 3
            initial_delay_seconds = 30
            period_seconds        = 10
            success_threshold     = 1
            timeout_seconds       = 1
          }

          volume_mount {
            name       = "${local.grafana_name}-pv"
            mount_path = "/var/lib/grafana"
          }
        }

        volume {
          name = "${local.grafana_name}-pv"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana-pvc.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana-service" {
  metadata {
    name      = "${local.grafana_name}-service"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  spec {
    selector = {
      app = local.grafana_name
    }
    port {
      port        = 80
      name        = "http"
      protocol    = "TCP"
      target_port = local.grafana_port
    }
  }
}

module "grafana_ingress" {
  source = "./modules/ingress"

  name            = "${local.grafana_name}-ingress"
  namespace       = kubernetes_namespace.grafana.metadata.0.name
  host            = "${local.grafana_name}.${local.domain}"
  service_name    = kubernetes_service.grafana-service.metadata[0].name
  service_port    = kubernetes_service.grafana-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.grafana_name}-tls"
  dns_target_ip   = local.master_node_ip
}

### --------------- ###

resource "grafana_folder" "infrastructure" {
  title = "Infrastructure"
}

resource "grafana_data_source" "prometheus" {
  provider = grafana

  type = "prometheus"
  name = "prometheus"
  url  = "https://${module.prometheus_ingress.ingress_host}"
  uid  = "ff3jpa1l4kbnkc"

  access_mode = "proxy"
  is_default  = true

  json_data_encoded = jsonencode({
    httpMethod        = "POST"
    tlsAuthWithCACert = true
  })

  secure_json_data_encoded = jsonencode({
    tlsCACert = data.sops_file.secrets.data["kubernetes_cluster_certificate"]
  })
}

resource "grafana_contact_point" "contact_point_home_assistant" {
  name = "HomeAssistant"

  webhook {
    url         = "http://home-assistant.home.arpa/api/webhook/-ZriIHkm1uzfZ88RKd-cgTWFs"
    http_method = "POST"
  }
}

resource "grafana_rule_group" "rule_group_infrastructure" {
  org_id           = 1
  name             = "High-Critical"
  folder_uid       = grafana_folder.infrastructure.uid
  interval_seconds = 60

  rule {
    name      = "DriveHealthSMARTTemp"
    condition = "B"

    data {
      ref_id = "A"

      relative_time_range {
        from = 600
        to   = 0
      }

      datasource_uid = grafana_data_source.prometheus.uid
      model          = "{\"disableTextWrap\":false,\"editorMode\":\"builder\",\"exemplar\":false,\"expr\":\"smartctl_device_temperature\",\"fullMetaSearch\":false,\"includeNullMetadata\":true,\"instant\":true,\"intervalMs\":1000,\"legendFormat\":\"{{device}}\",\"maxDataPoints\":43200,\"range\":false,\"refId\":\"A\",\"useBackend\":false}"
    }
    data {
      ref_id = "B"

      relative_time_range {
        from = 600
        to   = 0
      }

      datasource_uid = "__expr__"
      model          = "{\"conditions\":[{\"evaluator\":{\"params\":[70],\"type\":\"gt\"},\"operator\":{\"type\":\"and\"},\"query\":{\"params\":[\"C\"]},\"reducer\":{\"params\":[],\"type\":\"last\"},\"type\":\"query\"}],\"datasource\":{\"type\":\"__expr__\",\"uid\":\"__expr__\"},\"expression\":\"A\",\"intervalMs\":1000,\"maxDataPoints\":43200,\"refId\":\"B\",\"type\":\"threshold\"}"
    }

    no_data_state  = "NoData"
    exec_err_state = "Error"
    for            = "2m"
    annotations    = {}
    labels         = {}
    is_paused      = false

    notification_settings {
      contact_point = "HomeAssistant"
      group_by      = null
      mute_timings  = null
    }
  }
  rule {
    name      = "DriveHealethSMARTHealth"
    condition = "B"

    data {
      ref_id = "A"

      relative_time_range {
        from = 600
        to   = 0
      }

      datasource_uid = grafana_data_source.prometheus.uid
      model          = "{\"disableTextWrap\":false,\"editorMode\":\"builder\",\"expr\":\"smartctl_device_smart_status\",\"fullMetaSearch\":false,\"includeNullMetadata\":true,\"instant\":true,\"intervalMs\":1000,\"legendFormat\":\"__auto\",\"maxDataPoints\":43200,\"range\":false,\"refId\":\"A\",\"useBackend\":false}"
    }
    data {
      ref_id = "B"

      relative_time_range {
        from = 600
        to   = 0
      }

      datasource_uid = "__expr__"
      model          = "{\"conditions\":[{\"evaluator\":{\"params\":[1],\"type\":\"lt\"},\"operator\":{\"type\":\"and\"},\"query\":{\"params\":[\"C\"]},\"reducer\":{\"params\":[],\"type\":\"last\"},\"type\":\"query\"}],\"datasource\":{\"type\":\"__expr__\",\"uid\":\"__expr__\"},\"expression\":\"A\",\"intervalMs\":1000,\"maxDataPoints\":43200,\"refId\":\"B\",\"type\":\"threshold\"}"
    }

    no_data_state  = "NoData"
    exec_err_state = "Error"
    for            = "5m"
    annotations    = {}
    labels         = {}
    is_paused      = false

    notification_settings {
      contact_point = "HomeAssistant"
      group_by      = null
      mute_timings  = null
    }
  }
  rule {
    name      = "BTRFSErrors"
    condition = "C"

    data {
      ref_id = "A"

      relative_time_range {
        from = 600
        to   = 0
      }

      datasource_uid = grafana_data_source.prometheus.uid
      model          = "{\"disableTextWrap\":false,\"editorMode\":\"builder\",\"expr\":\"node_btrfs_device_errors_total\",\"fullMetaSearch\":false,\"includeNullMetadata\":true,\"instant\":true,\"intervalMs\":1000,\"legendFormat\":\"__auto\",\"maxDataPoints\":43200,\"range\":false,\"refId\":\"A\",\"useBackend\":false}"
    }
    data {
      ref_id = "C"

      relative_time_range {
        from = 600
        to   = 0
      }

      datasource_uid = "__expr__"
      model          = "{\"conditions\":[{\"evaluator\":{\"params\":[0],\"type\":\"gt\"},\"operator\":{\"type\":\"and\"},\"query\":{\"params\":[\"C\"]},\"reducer\":{\"params\":[],\"type\":\"last\"},\"type\":\"query\"}],\"datasource\":{\"type\":\"__expr__\",\"uid\":\"__expr__\"},\"expression\":\"A\",\"intervalMs\":1000,\"maxDataPoints\":43200,\"refId\":\"C\",\"type\":\"threshold\"}"
    }

    no_data_state  = "NoData"
    exec_err_state = "Error"
    for            = "1m"
    annotations    = {}
    labels         = {}
    is_paused      = false

    notification_settings {
      contact_point = grafana_contact_point.contact_point_home_assistant.name
      group_by      = null
      mute_timings  = null
    }
  }
}

resource "grafana_dashboard" "node_exporter_dashboard" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("./dashboards/node-exporter.json")
}

resource "grafana_dashboard" "smartctl_exporter_dashboard" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("./dashboards/smartctl-exporter.json")
}

resource "grafana_dashboard" "btrfs_exporter_dashboard" {
  folder      = grafana_folder.infrastructure.id
  config_json = file("./dashboards/btrfs.json")
}

