variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "codepush"
}


# Storage Configuration
variable "storage_location" {
  description = "Location for the GCS bucket (region or multi-region)"
  type        = string
  default     = "US"
}

variable "storage_versioning_enabled" {
  description = "Enable versioning for the GCS bucket"
  type        = bool
  default     = true
}

variable "storage_lifecycle_age_days" {
  description = "Number of days after which objects are deleted (lifecycle rule)"
  type        = number
  default     = 365
}

variable "storage_force_destroy" {
  description = "Force destroy the bucket even if it contains objects (use with caution)"
  type        = bool
  default     = false
}


# Application Configuration
variable "server_url" {
  description = "Server URL for the CodePush server"
  type        = string
  default     = ""
}

variable "emulated_mode" {
  description = "Enable emulated mode for development"
  type        = bool
  default     = false
}

variable "enable_logging" {
  description = "Enable application logging"
  type        = bool
  default     = true
}

variable "enable_account_registration" {
  description = "Enable account registration"
  type        = bool
  default     = true
}

variable "upload_size_limit_mb" {
  description = "Upload size limit in MB"
  type        = number
  default     = 200
}

variable "additional_env_vars" {
  description = "Additional environment variables for the application"
  type        = map(string)
  default     = {}
}

# Network Configuration

variable "custom_domain" {
  description = "Custom domain for the service (optional)"
  type        = string
  default     = ""
}

variable "enable_ssl" {
  description = "Enable SSL with Let's Encrypt (requires custom_domain)"
  type        = bool
  default     = true
}

# CI/CD Configuration
variable "enable_cicd" {
  description = "Enable CI/CD with Cloud Build"
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = ""
}

variable "github_branch" {
  description = "GitHub branch to trigger builds"
  type        = string
  default     = "main"
}


# VM Configuration (when deployment_type = "vm")
variable "vm_machine_type" {
  description = "Machine type for the VM"
  type        = string
  default     = "e2-standard-2"
}

variable "vm_image" {
  description = "VM image to use"
  type        = string
  default     = "projects/cos-cloud/global/images/family/cos-stable"
}

variable "vm_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 50
}

variable "vm_disk_type" {
  description = "Boot disk type"
  type        = string
  default     = "pd-standard"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = ""
}

variable "ssh_source_ranges" {
  description = "Source IP ranges for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_source_ranges" {
  description = "Source IP ranges for HTTP/HTTPS access"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "redis_password" {
  description = "Password for Redis (generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

# Fastly Configuration
variable "enable_fastly" {
  description = "Enable Fastly CDN"
  type        = bool
  default     = false
}

variable "fastly_domain" {
  description = "Domain name for Fastly service"
  type        = string
  default     = ""
}

variable "fastly_enable_tls" {
  description = "Enable TLS/SSL certificate for Fastly"
  type        = bool
  default     = true
}

variable "fastly_certificate_authority" {
  description = "Certificate authority for Fastly TLS"
  type        = string
  default     = "lets-encrypt"
}

variable "fastly_default_ttl" {
  description = "Default TTL for cached content (seconds)"
  type        = number
  default     = 3600
}

variable "fastly_rate_limit_allowlist" {
  description = "IP addresses/ranges to exclude from rate limiting"
  type = list(object({
    ip      = string
    subnet  = optional(number)
    comment = string
  }))
  default = []
}

# Missing variables
variable "deployment_type" {
  description = "Type of deployment (vm or cloudrun)"
  type        = string
  default     = "vm"
}

variable "github_client_id" {
  description = "GitHub OAuth client ID"
  type        = string
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "container_image" {
  description = "Container image to deploy"
  type        = string
  default     = "gcr.io/PROJECT_ID/codepush:latest"
}

# Labels
variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    environment = "production"
    application = "codepush-server"
    managed-by  = "terraform"
  }
}