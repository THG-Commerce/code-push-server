# Docker Setup for CodePush Server

This directory contains Docker configuration files to run the CodePush server in a containerized environment.

## Files

- [`Dockerfile`](Dockerfile) - Multi-stage Docker build configuration
- [`.dockerignore`](.dockerignore) - Files to exclude from Docker build context
- [`docker-compose.yml`](docker-compose.yml) - Docker Compose configuration for easy deployment

## Quick Start

### Using Docker Compose (Recommended)

1. **Build and start the server:**
   ```bash
   docker-compose up --build
   ```

2. **Access the server:**
   - HTTP: http://localhost:3000
   - HTTPS: https://localhost:8443 (if HTTPS is enabled)

3. **Stop the server:**
   ```bash
   docker-compose down
   ```

### Using Docker directly

1. **Build the image:**
   ```bash
   docker build -t code-push-server .
   ```

2. **Run the container:**
   ```bash
   docker run -p 3000:3000 -p 8443:8443 code-push-server
   ```

## Configuration

### Environment Variables

The server can be configured using environment variables. See [`.env.example`](.env.example) for all available options.

**Required for production:**
- `SERVER_URL` - The URL of your server
- `AZURE_STORAGE_ACCOUNT` - Azure storage account name
- `AZURE_STORAGE_ACCESS_KEY` - Azure storage access key
- Authentication provider credentials (GitHub, Microsoft, etc.)

**Development mode:**
- Set `DEBUG_DISABLE_AUTH=true` to disable authentication
- Set `EMULATED=true` to use local storage instead of Azure

### HTTPS Support

To enable HTTPS:

1. Place your SSL certificates in a `certs` directory:
   ```
   certs/
   ├── cert.crt
   └── cert.key
   ```

2. Mount the certificates in your container:
   ```bash
   docker run -p 8443:8443 -v ./certs:/app/certs:ro -e HTTPS=true code-push-server
   ```

3. Or uncomment the volume mount in [`docker-compose.yml`](docker-compose.yml)

### Redis Support

Redis is enabled by default in the Docker Compose setup for session storage and caching. The configuration includes:

- Redis 7 Alpine container
- Persistent data storage via Docker volume
- Automatic connection from the CodePush server

To disable Redis, comment out the Redis service and environment variables in [`docker-compose.yml`](docker-compose.yml).

## Production Deployment

For production deployment:

1. **Create a production environment file:**
   ```bash
   cp .env.example .env
   # Edit .env with your production values
   ```

2. **Use production Docker Compose override:**
   ```yaml
   # docker-compose.prod.yml
   version: '3.8'
   services:
     code-push-server:
       environment:
         - DEBUG_DISABLE_AUTH=false
       env_file:
         - .env
   ```

3. **Deploy:**
   ```bash
   docker-compose -f docker-compose.yml -f docker-compose.prod.yml up -d
   ```

## Health Checks

The container includes a health check that verifies the server is responding on the configured port. You can check the health status:

```bash
docker ps  # Shows health status
docker inspect <container_id> | grep Health  # Detailed health info
```

## Troubleshooting

### Build Issues

- Ensure you have sufficient disk space for the build
- Check that all required files are present and not excluded by [`.dockerignore`](.dockerignore)

### Runtime Issues

- Check container logs: `docker-compose logs code-push-server`
- Verify environment variables are set correctly
- Ensure required external services (Azure Storage, Redis) are accessible

### Port Conflicts

If ports 3000 or 8443 are already in use, modify the port mapping in [`docker-compose.yml`](docker-compose.yml):

```yaml
ports:
  - "3001:3000"  # Map to different host port
  - "8444:8443"
```

## Security Considerations

- The container runs as a non-root user (`codepush`) for security
- Sensitive data should be provided via environment variables or mounted secrets
- In production, disable debug authentication and use proper OAuth providers
- Use HTTPS in production environments
- Regularly update the base Node.js image for security patches