terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.39.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
    pihole = {
      source  = "ryanwholey/pihole"
      version = "2.0.0-beta.1"
    }
  }
}

provider "google" {
  project = "home-lab-391312"
}

provider "kubernetes" {
  host = "https://${local.master_node_ip}:6443"

  token    = var.deployer_service_account_token
  insecure = true
}

provider "helm" {
  kubernetes {
    host = "https://${local.master_node_ip}:6443"

    token    = var.deployer_service_account_token
    insecure = true
  }
}

provider "sops" {}

provider "pihole" {
  url = "http://pi-hole.${local.domain}"

  # Pi-hole sets the API token to the admin password hashed twiced via SHA-256
  # api_token = sha256(sha256(data.sops_file.secrets.data["pihole_admin_password"]))
  password = data.sops_file.secrets.data["pihole_admin_password"]
}
