# Custom VCL for request processing

# Rate limiting for API endpoints
if (req.url ~ "^/api/" && !client.ip ~ rate_limit_allowlist) {
  if (ratelimit.check_rate(
    client.ip,
    100,  # 100 requests
    1m,   # per minute
    "api_rate_limit"
  )) {
    error 429 "Rate limit exceeded";
  }
}

# Security: Block suspicious requests
if (req.http.User-Agent ~ "(bot|crawler|spider)" && req.url ~ "^/api/") {
  error 403 "Forbidden";
}

# Normalize URLs for better caching
set req.url = regsub(req.url, "\?$", "");

# Handle CORS preflight requests
if (req.method == "OPTIONS") {
  return(synth(200, "OK"));
}

# Force HTTPS for API endpoints
if (!req.http.Fastly-SSL && req.url ~ "^/api/") {
  error 801 "Force SSL";
}

# Set backend based on request type
if (req.url ~ "^/api/") {
  set req.backend = gcp_backend;
  # Don't cache API requests by default
  set req.http.X-Pass = "1";
} else {
  set req.backend = gcp_backend;
}