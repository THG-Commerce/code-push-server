#!/bin/bash

# CodePush Server VM Startup Script
set -euo pipefail

# Script hash for change detection
SCRIPT_HASH="${script_hash}"
HASH_FILE="/opt/codepush/.script-hash"
SETUP_COMPLETE_FILE="/opt/codepush/.setup-complete"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/codepush-setup.log
}

# Create codepush directory
mkdir -p /opt/codepush

# Check if script has changed or setup is incomplete
SHOULD_RUN=false
if [[ ! -f "$HASH_FILE" ]] || [[ "$(cat $HASH_FILE 2>/dev/null || echo '')" != "$SCRIPT_HASH" ]]; then
    log "Script changed or first run detected (hash: $SCRIPT_HASH)"
    SHOULD_RUN=true
elif [[ ! -f "$SETUP_COMPLETE_FILE" ]]; then
    log "Setup incomplete, re-running..."
    SHOULD_RUN=true
else
    log "Script unchanged and setup complete, skipping..."
    exit 0
fi

if [[ "$SHOULD_RUN" == "true" ]]; then
    log "Starting CodePush Server setup..."
    echo "$SCRIPT_HASH" > "$HASH_FILE"
fi

# Update the system
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install required packages
log "Installing Docker and dependencies..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    redis-server \
    nginx \
    certbot \
    python3-certbot-nginx

# Install Docker (idempotent)
if ! command -v docker &> /dev/null; then
    log "Setting up Docker repository..."
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
else
    log "Docker already installed, skipping..."
fi

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Configure Redis
log "Configuring Redis..."
sed -i 's/^bind 127.0.0.1/bind 127.0.0.1/' /etc/redis/redis.conf
sed -i 's/^# requirepass foobared/requirepass ${redis_password}/' /etc/redis/redis.conf

# Enable and start Redis
systemctl enable redis-server
systemctl start redis-server

# Create application directory
log "Setting up application directories..."
mkdir -p /opt/codepush
mkdir -p /etc/codepush
mkdir -p /var/log/codepush

# Create environment file
log "Creating environment configuration..."
cat > /etc/codepush/.env << EOF
# Server Configuration
SERVER_URL=${server_url}
PORT=3000

# Storage Configuration
STORAGE_TYPE=gcs
GCS_BUCKET_NAME=${gcs_bucket_name}
GOOGLE_CLOUD_PROJECT=${project_id}

# Redis Configuration
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_KEY=${redis_password}

# Application Settings
EMULATED=${emulated_mode}
LOGGING=${enable_logging}
ENABLE_ACCOUNT_REGISTRATION=${enable_account_registration}
UPLOAD_SIZE_LIMIT_MB=${upload_size_limit_mb}

# GitHub OAuth (if provided)
%{ if github_client_id != "" }
GITHUB_CLIENT_ID=${github_client_id}
GITHUB_CLIENT_SECRET=${github_client_secret}
%{ endif }

# Additional environment variables
%{ for key, value in additional_env_vars }
${key}=${value}
%{ endfor }
EOF

# Set proper permissions
chown root:root /etc/codepush/.env
chmod 600 /etc/codepush/.env

# Configure Docker authentication for GCR
log "Setting up Docker authentication for GCR..."
gcloud auth configure-docker --quiet

# Pull and run the CodePush container
log "Pulling and starting CodePush container..."
docker pull ${container_image}

# Create Docker run script
cat > /opt/codepush/run-container.sh << 'EOF'
#!/bin/bash
docker stop codepush-server || true
docker rm codepush-server || true

docker run -d \
  --name codepush-server \
  --restart unless-stopped \
  -p 127.0.0.1:3000:3000 \
  -p 127.0.0.1:8443:8443 \
  --env-file /etc/codepush/.env \
  -v /var/log/codepush:/app/logs \
  ${container_image}
EOF

chmod +x /opt/codepush/run-container.sh
/opt/codepush/run-container.sh

# Configure Nginx as reverse proxy
log "Configuring Nginx..."
cat > /etc/nginx/sites-available/codepush << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=general:10m rate=5r/s;
    
    # Proxy configuration
    location / {
        limit_req zone=general burst=10 nodelay;
        
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # API endpoints with stricter rate limiting
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-CodePush-SDK-Version" always;
        
        if ($request_method = 'OPTIONS') {
            return 204;
        }
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:3000/;
        access_log off;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/codepush /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test and reload Nginx
nginx -t
systemctl enable nginx
systemctl restart nginx

# Setup log rotation
log "Setting up log rotation..."
cat > /etc/logrotate.d/codepush << 'EOF'
/var/log/codepush/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        docker restart codepush-server > /dev/null 2>&1 || true
    endscript
}
EOF

# Create systemd service for the container
log "Creating systemd service..."
cat > /etc/systemd/system/codepush.service << 'EOF'
[Unit]
Description=CodePush Server Container
Requires=docker.service redis-server.service
After=docker.service redis-server.service

[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/opt/codepush/run-container.sh
ExecStop=/usr/bin/docker stop codepush-server
ExecStopPost=/usr/bin/docker rm codepush-server
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable codepush.service

# Setup monitoring script
log "Setting up monitoring..."
cat > /opt/codepush/monitor.sh << 'EOF'
#!/bin/bash
if ! docker ps | grep -q codepush-server; then
    echo "$(date): CodePush container not running, restarting..." >> /var/log/codepush/monitor.log
    /opt/codepush/run-container.sh
fi
EOF

chmod +x /opt/codepush/monitor.sh

# Add cron job for monitoring
echo "*/5 * * * * root /opt/codepush/monitor.sh" >> /etc/crontab

# Setup firewall
log "Configuring firewall..."
ufw --force enable
ufw allow ssh
ufw allow http
ufw allow https

# Setup SSL certificates if custom domain is provided
%{ if custom_domain != "" && enable_ssl }
log "Setting up SSL certificates for ${custom_domain}..."

# Update Nginx config for HTTPS
cat > /etc/nginx/sites-available/codepush << 'EOF'
server {
    listen 80;
    server_name ${custom_domain};
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${custom_domain};
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${custom_domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${custom_domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=general:10m rate=5r/s;
    
    # Proxy configuration
    location / {
        limit_req zone=general burst=10 nodelay;
        
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # API endpoints with stricter rate limiting
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # CORS headers
        add_header Access-Control-Allow-Origin "*" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-CodePush-SDK-Version" always;
        
        if ($request_method = 'OPTIONS') {
            return 204;
        }
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:3000/;
        access_log off;
    }
}
EOF

# Get SSL certificate
if [[ ! -f "/etc/letsencrypt/live/${custom_domain}/fullchain.pem" ]]; then
    log "Obtaining SSL certificate from Let's Encrypt..."
    certbot certonly --nginx -d ${custom_domain} --non-interactive --agree-tos --email admin@${custom_domain} --redirect
else
    log "SSL certificate already exists, skipping..."
fi

# Setup certificate renewal
log "Setting up automatic certificate renewal..."
echo "0 12 * * * root /usr/bin/certbot renew --quiet && systemctl reload nginx" >> /etc/crontab

nginx -t && systemctl reload nginx
%{ else }
log "SSL not enabled or no custom domain provided, using HTTP only"
%{ endif }

log "CodePush Server setup completed successfully!"
log "Container status: $(docker ps --filter name=codepush-server --format 'table {{.Names}}\t{{.Status}}')"
log "Redis status: $(systemctl is-active redis-server)"
log "Nginx status: $(systemctl is-active nginx)"

# Mark setup as complete
echo "$(date '+%Y-%m-%d %H:%M:%S')" > "$SETUP_COMPLETE_FILE"
log "Setup marked as complete with hash: $SCRIPT_HASH"