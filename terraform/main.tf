terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.42.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
    pihole = {
      source  = "ryanwholey/pihole"
      version = "2.0.0-beta.1"
    }
    grafana = {
      source  = "grafana/grafana"
      version = "4.42.0"
    }
  }
}

provider "google" {
  project = "home-lab-391312"
}

provider "kubernetes" {
  host = "https://${local.master_node_ip}:6443"

  token    = data.sops_file.secrets.data["deployer_service_account_token"]
  insecure = true
}

provider "helm" {
  kubernetes {
    host = "https://${local.master_node_ip}:6443"

    token    = data.sops_file.secrets.data["deployer_service_account_token"]
    insecure = true
  }
}

provider "sops" {}

provider "pihole" {
  url = "http://192.168.1.67:8080"

  # Pi-hole sets the API token to the admin password hashed twiced via SHA-256
  # api_token = sha256(sha256(data.sops_file.secrets.data["pihole_admin_password"]))
  password = data.sops_file.secrets.data["pihole_admin_password"]
}

provider "grafana" {
  url     = "https://${local.grafana_name}.${local.domain}"
  auth    = "${data.sops_file.secrets.data["grafana_admin_user"]}:${data.sops_file.secrets.data["grafana_admin_password"]}"
  ca_cert = data.sops_file.secrets.data["kubernetes_cluster_certificate"]
}
