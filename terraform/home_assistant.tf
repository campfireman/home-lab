locals {
  ha_external_ip = "192.168.1.67"
  ha_name        = "home-assistant"
  ha_port        = 8123
  ha_database    = "home_assistant"
}

resource "kubernetes_namespace_v1" "ha" {
  metadata {
    name = local.ha_name
  }
}

resource "kubernetes_service_v1" "ha-service" {
  metadata {
    name      = "${local.ha_name}-ext"
    namespace = kubernetes_namespace_v1.ha.metadata[0].name
  }
  spec {
    port {
      name        = "http"
      port        = local.ha_port
      target_port = local.ha_port
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_endpoints_v1" "ha" {
  metadata {
    name      = "${local.ha_name}-ext"
    namespace = kubernetes_namespace_v1.ha.metadata[0].name
  }
  subset {
    address {
      ip = local.ha_external_ip
    }
    port {
      name = "http"
      port = local.ha_port
    }
  }
}

module "ha_ingress" {
  source = "./modules/ingress"

  name            = "${local.ha_name}-ingress"
  namespace       = kubernetes_namespace_v1.ha.metadata.0.name
  host            = "${local.ha_name}.${local.domain}"
  service_name    = kubernetes_service_v1.ha-service.metadata[0].name
  service_port    = kubernetes_service_v1.ha-service.spec[0].port[0].port
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "${local.ha_name}-tls"
  dns_target_ip   = local.master_node_ip
}

# Long-term storage for the Home Assistant recorder. Ansible points the
# recorder on zimaboard to this database (see roles/zimaboard).
resource "postgresql_role" "ha" {
  name     = local.ha_database
  login    = true
  password = data.sops_file.secrets.data["postgres_home_assistant_password"]
}

resource "postgresql_database" "ha" {
  name  = local.ha_database
  owner = postgresql_role.ha.name
}

# Read-only role for analysis, for example from Grafana.
resource "postgresql_role" "ha_reader" {
  name     = "${local.ha_database}_reader"
  login    = true
  password = data.sops_file.secrets.data["postgres_home_assistant_reader_password"]
}

resource "postgresql_grant" "ha_reader_connect" {
  database    = postgresql_database.ha.name
  role        = postgresql_role.ha_reader.name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "ha_reader_schema" {
  database    = postgresql_database.ha.name
  role        = postgresql_role.ha_reader.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

# Home Assistant creates its tables after this apply. Default privileges give
# the reader SELECT on each table that the home_assistant role creates.
resource "postgresql_default_privileges" "ha_reader_tables" {
  database    = postgresql_database.ha.name
  role        = postgresql_role.ha_reader.name
  owner       = postgresql_role.ha.name
  schema      = "public"
  object_type = "table"
  privileges  = ["SELECT"]
}
