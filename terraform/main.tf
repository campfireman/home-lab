terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.2"
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
