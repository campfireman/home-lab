terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.37.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
  }
}

provider "google" {
  project = "home-lab-391312"
}

provider "kubernetes" {
  host = "https://192.168.1.102:6443"

  token    = var.deployer_service_account_token
  insecure = true
}

provider "helm" {
  kubernetes {
    host = "https://192.168.1.102:6443"

    token    = var.deployer_service_account_token
    insecure = true
  }
}

provider "sops" {}
