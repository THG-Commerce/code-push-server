terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    fastly = {
      source  = "fastly/fastly"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_on_destroy = false
}

# VPC for the deployment
resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false
  
  depends_on = [google_project_service.apis]
}

# Subnet for the VM
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Firewall rule for HTTP/HTTPS traffic
resource "google_compute_firewall" "allow_http" {
  name    = "${var.name_prefix}-allow-http"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = var.allowed_source_ranges
  target_tags   = ["codepush-server"]
}

# Firewall rule for SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.name_prefix}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["codepush-server"]
}

# Static IP for the VM
resource "google_compute_address" "vm_ip" {
  name   = "${var.name_prefix}-ip"
  region = var.region
}

# Global static IP for Cloud Run (when deployment_type != "vm")
resource "google_compute_global_address" "cloudrun_ip" {
  count = var.deployment_type != "vm" ? 1 : 0
  name  = "${var.name_prefix}-global-ip"
}

# Google Cloud Storage bucket for CodePush packages
resource "google_storage_bucket" "codepush_storage" {
  name          = "${var.project_id}-${var.name_prefix}-storage"
  location      = var.storage_location
  force_destroy = var.storage_force_destroy
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = var.storage_versioning_enabled
  }
  
  lifecycle_rule {
    condition {
      age = var.storage_lifecycle_age_days
    }
    action {
      type = "Delete"
    }
  }
  
  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["*"]
    max_age_seconds = 3600
  }
  
  labels = var.labels
  
  depends_on = [google_project_service.apis]
}

# Service account for the VM
resource "google_service_account" "codepush_sa" {
  account_id   = "${var.name_prefix}-vm-sa"
  display_name = "CodePush VM Service Account"
  description  = "Service account for CodePush VM"
}

# IAM policy for VM to access Storage
resource "google_storage_bucket_iam_member" "codepush_storage" {
  bucket = google_storage_bucket.codepush_storage.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.codepush_sa.email}"
}

# Startup script for the VM
locals {
  startup_script_template = file("${path.module}/startup-script.sh")
  startup_script_hash = md5(local.startup_script_template)
  
  startup_script = templatefile("${path.module}/startup-script.sh", {
    project_id                   = var.project_id
    server_url                   = var.server_url != "" ? var.server_url : "http://${google_compute_address.vm_ip.address}:3000"
    emulated_mode               = var.emulated_mode
    enable_logging              = var.enable_logging
    enable_account_registration = var.enable_account_registration
    upload_size_limit_mb        = var.upload_size_limit_mb
    gcs_bucket_name             = google_storage_bucket.codepush_storage.name
    github_client_id            = var.github_client_id
    github_client_secret        = var.github_client_secret
    additional_env_vars         = var.additional_env_vars
    container_image             = var.container_image
    redis_password              = var.redis_password
    custom_domain               = var.custom_domain
    enable_ssl                  = var.enable_ssl
    script_hash                 = local.startup_script_hash
  })
}

# VM instance
resource "google_compute_instance" "codepush_vm" {
  name         = "${var.name_prefix}-vm"
  machine_type = var.vm_machine_type
  zone         = "${var.region}-a"
  
  tags = ["codepush-server"]
  
  boot_disk {
    initialize_params {
      image = var.vm_image
      size  = var.vm_disk_size_gb
      type  = var.vm_disk_type
    }
  }
  
  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name
    
    access_config {
      nat_ip = google_compute_address.vm_ip.address
    }
  }
  
  service_account {
    email  = google_service_account.codepush_sa.email
    scopes = ["cloud-platform"]
  }
  
  metadata = {
    startup-script = local.startup_script
    ssh-keys       = var.ssh_public_key != "" ? "codepush:${var.ssh_public_key}" : ""
    script-hash    = local.startup_script_hash
  }
  
  labels = var.labels
  
  depends_on = [google_project_service.apis]
}

# Cloud Build trigger for automated deployments (optional)
resource "google_cloudbuild_trigger" "deploy_trigger" {
  count = var.enable_cicd ? 1 : 0
  
  name        = "${var.name_prefix}-deploy"
  description = "Deploy CodePush Server to VM"
  
  github {
    owner = var.github_owner
    name  = var.github_repo
    push {
      branch = var.github_branch
    }
  }
  
  build {
    step {
      name = "gcr.io/cloud-builders/docker"
      args = [
        "build",
        "-t", "gcr.io/${var.project_id}/${var.name_prefix}:$COMMIT_SHA",
        "-f", "api/Dockerfile",
        "./api"
      ]
    }
    
    step {
      name = "gcr.io/cloud-builders/docker"
      args = ["push", "gcr.io/${var.project_id}/${var.name_prefix}:$COMMIT_SHA"]
    }
    
    step {
      name = "gcr.io/cloud-builders/gcloud"
      args = [
        "compute", "ssh", google_compute_instance.codepush_vm.name,
        "--zone", "${var.region}-a",
        "--command", "sudo docker pull gcr.io/${var.project_id}/${var.name_prefix}:$COMMIT_SHA && sudo docker stop codepush-server || true && sudo docker rm codepush-server || true && sudo docker run -d --name codepush-server --restart unless-stopped -p 3000:3000 -p 8443:8443 --env-file /etc/codepush/.env gcr.io/${var.project_id}/${var.name_prefix}:$COMMIT_SHA"
      ]
    }
  }
  
  depends_on = [google_project_service.apis]
}