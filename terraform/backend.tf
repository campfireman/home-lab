terraform {
  backend "gcs" {
    bucket = "home-lab-tfstate"
  }
}