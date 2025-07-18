# Custom VCL for response delivery

# Add cache status headers for debugging
set resp.http.X-Cache-Status = if(fastly_info.state ~ "^(HIT|MISS)$", fastly_info.state, "UNKNOWN");
set resp.http.X-Cache-Hits = obj.hits;

# Add CodePush specific headers
set resp.http.X-CodePush-Server = "Fastly CDN";
set resp.http.X-Served-By = server.hostname;

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

# Add Fastly-specific rate limit headers
if (req.url ~ "^/api/") {
  set resp.http.X-RateLimit-Limit = "100";
  set resp.http.X-RateLimit-Remaining = ratelimit.remaining_requests(
    client.ip,
    100,
    1m,
    "api_rate_limit"
  );
}

# Performance optimization headers
set resp.http.X-Frame-Options = "DENY";
set resp.http.X-Content-Type-Options = "nosniff";
set resp.http.Referrer-Policy = "strict-origin-when-cross-origin";

# Remove internal headers
unset resp.http.X-Varnish;
unset resp.http.Via;