# Custom VCL for CodePush request processing

# CodePush-specific caching logic
# CLI operations should NEVER be cached
if (req.url ~ "^/(api/|accessKeys|account|apps/)" && !(req.url ~ "^/(updateCheck|v0\.1/public/codepush/update_check)")) {
  set req.http.X-Pass = "1";
  set req.http.X-CodePush-Type = "cli";
  # Strict rate limiting for CLI operations (authenticated users)
  if (!client.ip ~ rate_limit_allowlist) {
    if (ratelimit.check_rate(
      client.ip,
      60,   # 60 requests
      1m,   # per minute
      "cli_rate_limit"
    )) {
      error 429 "CLI rate limit exceeded";
    }
  }
}

# Status reporting should not be cached but less strict rate limiting
if (req.url ~ "^/(reportStatus|v0\.1/public/codepush/report_status)") {
  set req.http.X-Pass = "1";
  set req.http.X-CodePush-Type = "status";
  if (!client.ip ~ rate_limit_allowlist) {
    if (ratelimit.check_rate(
      client.ip,
      200,  # 200 requests
      1m,   # per minute
      "status_rate_limit"
    )) {
      error 429 "Status reporting rate limit exceeded";
    }
  }
}

# App update checks can be cached but with shorter TTL
if (req.url ~ "^/(updateCheck|v0\.1/public/codepush/update_check)") {
  set req.http.X-CodePush-Type = "update";
  # More generous rate limiting for app update checks
  if (!client.ip ~ rate_limit_allowlist) {
    if (ratelimit.check_rate(
      client.ip,
      300,  # 300 requests
      1m,   # per minute
      "update_rate_limit"
    )) {
      error 429 "Update check rate limit exceeded";
    }
  }
}

# Package downloads should be cached aggressively
if (req.url ~ "^/packages/" || req.url ~ "\.zip$") {
  set req.http.X-CodePush-Type = "package";
  # Very generous rate limiting for package downloads
  if (!client.ip ~ rate_limit_allowlist) {
    if (ratelimit.check_rate(
      client.ip,
      1000, # 1000 requests
      1m,   # per minute
      "download_rate_limit"
    )) {
      error 429 "Download rate limit exceeded";
    }
  }
}

# Security: Block suspicious requests on management endpoints
if (req.http.User-Agent ~ "(bot|crawler|spider)" && req.http.X-CodePush-Type == "cli") {
  error 403 "Automated access to management API forbidden";
}

# Normalize URLs for better caching
set req.url = regsub(req.url, "\?$", "");

# Handle CORS preflight requests
if (req.method == "OPTIONS") {
  return(synth(200, "OK"));
}

# Force HTTPS for all API endpoints
if (!req.http.Fastly-SSL && req.url ~ "^/(api/|updateCheck|v0\.1/|packages/|accessKeys|account|apps/)") {
  error 801 "Force SSL";
}

# Set backend
set req.backend = gcp_backend;