terraform {
  required_version = ">= 1.6.0" # OpenTofu

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0, < 8.0.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3.0, < 3.0.0"
    }
  }
}

# Auth: Application Default Credentials (`gcloud auth application-default login`).
# No service account key files (see ../CLAUDE.md).
provider "google" {
  project = var.project_id
  region  = local.region
  zone    = var.zone
}
