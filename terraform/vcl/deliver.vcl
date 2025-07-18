# Custom VCL for CodePush response delivery

# Add cache status headers for debugging
set resp.http.X-Cache-Status = if(fastly_info.state ~ "^(HIT|MISS)$", fastly_info.state, "UNKNOWN");
set resp.http.X-Cache-Hits = obj.hits;

# Add CodePush specific headers
set resp.http.X-CodePush-Server = "Fastly CDN";
set resp.http.X-Served-By = server.hostname;

# Add cache type information based on request type
if (req.http.X-CodePush-Type) {
  set resp.http.X-CodePush-Type = req.http.X-CodePush-Type;
}

# Remove backend response time for security
unset resp.http.X-Runtime;
unset resp.http.X-Response-Time;

# Handle CORS for all responses
if (req.method == "OPTIONS") {
  set resp.http.Access-Control-Allow-Origin = "*";
  set resp.http.Access-Control-Allow-Methods = "GET, POST, PUT, DELETE, OPTIONS";
  set resp.http.Access-Control-Allow-Headers = "Content-Type, Authorization, X-CodePush-SDK-Version";
  set resp.http.Access-Control-Max-Age = "86400";
  set resp.status = 200;
  return(deliver);
}

# Add rate limit headers based on endpoint type
if (req.http.X-CodePush-Type == "cli") {
  set resp.http.X-RateLimit-Limit = "60";
  set resp.http.X-RateLimit-Remaining = ratelimit.remaining_requests(
    client.ip,
    60,
    1m,
    "cli_rate_limit"
  );
  # Ensure CLI responses are never cached
  set resp.http.Cache-Control = "no-cache, no-store, must-revalidate";
  set resp.http.Pragma = "no-cache";
  set resp.http.Expires = "0";
} elsif (req.http.X-CodePush-Type == "update") {
  set resp.http.X-RateLimit-Limit = "300";
  set resp.http.X-RateLimit-Remaining = ratelimit.remaining_requests(
    client.ip,
    300,
    1m,
    "update_rate_limit"
  );
} elsif (req.http.X-CodePush-Type == "status") {
  set resp.http.X-RateLimit-Limit = "200";
  set resp.http.X-RateLimit-Remaining = ratelimit.remaining_requests(
    client.ip,
    200,
    1m,
    "status_rate_limit"
  );
  # Ensure status reports are never cached
  set resp.http.Cache-Control = "no-cache, no-store, must-revalidate";
} elsif (req.http.X-CodePush-Type == "package") {
  set resp.http.X-RateLimit-Limit = "1000";
  set resp.http.X-RateLimit-Remaining = ratelimit.remaining_requests(
    client.ip,
    1000,
    1m,
    "download_rate_limit"
  );
}

# Performance optimization headers
set resp.http.X-Frame-Options = "DENY";
set resp.http.X-Content-Type-Options = "nosniff";
set resp.http.Referrer-Policy = "strict-origin-when-cross-origin";

# Remove internal headers
unset resp.http.X-Varnish;
unset resp.http.Via;
unset resp.http.X-CodePush-Type;  # Don't expose internal routing headers