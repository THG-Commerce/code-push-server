# Fastly provider configuration

# Fastly service configuration
resource "fastly_service_vcl" "codepush_service" {
  count = var.enable_fastly ? 1 : 0
  
  name = "${var.name_prefix}-service"
  
  # Domain configuration
  domain {
    name = var.fastly_domain
  }
  
  # Backend configuration - GCP Load Balancer or VM
  backend {
    name    = "gcp_backend"
    address = var.deployment_type == "vm" ? google_compute_address.vm_ip.address : google_compute_global_address.cloudrun_ip[0].address
    port    = var.deployment_type == "vm" ? (var.custom_domain != "" ? 443 : 3000) : 443
    use_ssl = var.deployment_type == "vm" ? (var.custom_domain != "" ? true : false) : true
    
    # Health check configuration
    healthcheck = "codepush_healthcheck"
    
    # Connection settings
    connect_timeout       = 5000
    first_byte_timeout    = 60000
    between_bytes_timeout = 10000
    
    # SSL configuration
    ssl_cert_hostname = var.custom_domain != "" ? var.custom_domain : ""
    ssl_sni_hostname  = var.custom_domain != "" ? var.custom_domain : ""
  }
  
  # Health check
  healthcheck {
    name           = "codepush_healthcheck"
    host           = var.fastly_domain
    path           = "/"
    method         = "GET"
    expected_response = 200
    check_interval    = 30000
    timeout          = 5000
    initial          = 2
    threshold        = 3
    window          = 5
  }
  
  # Conditions for different request types
  condition {
    name      = "api_requests"
    type      = "REQUEST"
    statement = "req.url ~ \"^/api/\""
  }
  
  condition {
    name      = "static_assets"
    type      = "REQUEST"
    statement = "req.url ~ \"\\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$\""
  }
  
  condition {
    name      = "package_downloads"
    type      = "REQUEST"
    statement = "req.url ~ \"^/packages/\" || req.url ~ \"\\.zip$\""
  }
  
  # Response conditions
  condition {
    name      = "cacheable_response"
    type      = "RESPONSE"
    statement = "beresp.status == 200 && beresp.http.Cache-Control !~ \"no-cache|no-store|private\""
  }
  
  # Headers for API requests
  header {
    name        = "api_cors_origin"
    action      = "set"
    type        = "response"
    destination = "http.Access-Control-Allow-Origin"
    source      = "\"*\""
    request_condition   = "api_requests"
  }
  
  header {
    name        = "api_cors_methods"
    action      = "set"
    type        = "response"
    destination = "http.Access-Control-Allow-Methods"
    source      = "\"GET, POST, PUT, DELETE, OPTIONS\""
    request_condition   = "api_requests"
  }
  
  header {
    name        = "api_cors_headers"
    action      = "set"
    type        = "response"
    destination = "http.Access-Control-Allow-Headers"
    source      = "\"Content-Type, Authorization, X-CodePush-SDK-Version\""
    request_condition   = "api_requests"
  }
  
  # Caching headers for static assets
  header {
    name        = "static_cache_control"
    action      = "set"
    type        = "response"
    destination = "http.Cache-Control"
    source      = "\"public, max-age=31536000, immutable\""
    request_condition   = "static_assets"
  }
  
  # Caching for package downloads
  header {
    name        = "package_cache_control"
    action      = "set"
    type        = "response"
    destination = "http.Cache-Control"
    source      = "\"public, max-age=86400\""
    request_condition   = "package_downloads"
  }
  
  # Security headers
  header {
    name        = "security_hsts"
    action      = "set"
    type        = "response"
    destination = "http.Strict-Transport-Security"
    source      = "\"max-age=31536000; includeSubDomains\""
  }
  
  header {
    name        = "security_content_type"
    action      = "set"
    type        = "response"
    destination = "http.X-Content-Type-Options"
    source      = "\"nosniff\""
  }
  
  header {
    name        = "security_frame_options"
    action      = "set"
    type        = "response"
    destination = "http.X-Frame-Options"
    source      = "\"DENY\""
  }
  
  # Remove server information
  header {
    name        = "remove_server_header"
    action      = "delete"
    type        = "response"
    destination = "http.Server"
  }
  
  # ACL for rate limiting allowlist
  dynamic "acl" {
    for_each = length(var.fastly_rate_limit_allowlist) > 0 ? [1] : []
    content {
      name = "rate_limit_allowlist"
    }
  }

  # VCL snippets for custom logic
  snippet {
    name     = "recv_snippet"
    type     = "recv"
    priority = 100
    content  = file("${path.module}/vcl/recv.vcl")
  }
  
  snippet {
    name     = "deliver_snippet"
    type     = "deliver"
    priority = 100
    content  = file("${path.module}/vcl/deliver.vcl")
  }
  
  # Force TLS/SSL is handled by the TLS subscription
  
  # Default TTL settings
  default_ttl = var.fastly_default_ttl
  
  # Activate the service
  activate = true
  
  # Version comment
  version_comment = "CodePush Server CDN Configuration"
}

# Fastly domain validation (optional DNS record)
resource "fastly_tls_subscription" "codepush_tls" {
  count = var.enable_fastly && var.fastly_enable_tls ? 1 : 0
  
  domains = [var.fastly_domain]
  
  certificate_authority = var.fastly_certificate_authority
  
  depends_on = [fastly_service_vcl.codepush_service]
}

# ACL entries for rate limiting allowlist
resource "fastly_service_acl_entries" "rate_limit_allowlist" {
  count = var.enable_fastly && length(var.fastly_rate_limit_allowlist) > 0 ? 1 : 0
  
  service_id = fastly_service_vcl.codepush_service[0].id
  acl_id     = [for acl in fastly_service_vcl.codepush_service[0].acl : acl.acl_id if acl.name == "rate_limit_allowlist"][0]
  
  dynamic "entry" {
    for_each = var.fastly_rate_limit_allowlist
    content {
      ip      = entry.value.ip
      subnet  = entry.value.subnet
      comment = entry.value.comment
    }
  }
}