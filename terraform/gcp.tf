resource "google_storage_bucket" "static_website_bucket" {
  name          = "blog.ture.dev"
  location      = "europe-west1"
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }

  force_destroy = true
}

resource "google_storage_bucket_iam_member" "viewer" {
  bucket = google_storage_bucket.static_website_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers" # Public access for a static website
}

