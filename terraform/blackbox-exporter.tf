locals {
  blackbox_name = "blackbox-exporter"
}

resource "kubernetes_namespace" "blackbox-exporter" {
 metadata {
    name = local.blackbox_name
 } 
}

resource "kubernetes_config_map" "blackbox_config" {
  metadata {
    name      = "${local.blackbox_name}-config"
    namespace = kubernetes_namespace.blackbox-exporter.metadata[0].name
  }

  data = {
    "blackbox.yml" = <<EOF
modules:
  http_2xx:
    prober: http
    http:
      preferred_ip_protocol: "ip4"
  http_post_2xx:
    prober: http
    http:
      method: POST
  tcp_connect:
    prober: tcp
  pop3s_banner:
    prober: tcp
    tcp:
      query_response:
        - expect: "^+OK"
      tls: true
      tls_config:
        insecure_skip_verify: false
  ssh_banner:
    prober: tcp
    tcp:
      query_response:
        - expect: "^SSH-2.0-"
  irc_banner:
    prober: tcp
    tcp:
      query_response:
        - send: "NICK prober"
        - send: "USER prober prober prober :prober"
        - expect: "PING :([^ ]+)"
          send: "PONG ${1}"
        - expect: "^:[^ ]+ 001"
  icmp:
    prober: icmp
    timeout: 5s
    icmp:
      preferred_ip_protocol: "ip4"
EOF
  }
}

resource "kubernetes_deployment" "blackbox_exporter" {
  metadata {
    name      = local.blackbox_name
    namespace = kubernetes_namespace.blackbox-exporter.metadata[0].name
    labels = {
      app = local.blackbox_name
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = local.blackbox_name
      }
    }

    template {
      metadata {
        labels = {
          app = local.blackbox_name
        }
        annotations = {
          "checksum/config" = sha256(kubernetes_config_map.blackbox_config.data["blackbox.yml"])
        }
      }

      spec {
        container {
          name  = "blackbox-exporter"
          image = "prom/blackbox-exporter:v0.28.0"
          
          args = [
            "--config.file=/etc/blackbox_exporter/blackbox.yml"
          ]

          port {
            container_port = 9115
            name           = "http"
          }

          security_context {
            read_only_root_filesystem = true
            run_as_non_root           = true
            run_as_user               = 1000
            capabilities {
              add = ["NET_RAW"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/blackbox_exporter"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.blackbox_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "blackbox_exporter" {
  metadata {
    name      = local.blackbox_name
    namespace = kubernetes_namespace.blackbox-exporter.metadata[0].name
    labels = {
      app     = local.blackbox_name
    }
  }

  spec {
    selector = {
      app = local.blackbox_name
    }
    port {
      port        = 9115
      target_port = 9115
      name        = "http"
    }
  }
}
