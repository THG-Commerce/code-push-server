# Build stage
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files first for better Docker layer caching
COPY package*.json ./

# Install all dependencies (including dev dependencies needed for build)
RUN npm install

# Copy source code
COPY . .

# Build the TypeScript application
RUN npm run build

# Production stage
FROM node:18-alpine AS production

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install only production dependencies
RUN npm ci --only=production

# Copy built application from builder stage
COPY --from=builder /app/bin ./bin

# Create a non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S codepush -u 1001

# Create directories for optional features
RUN mkdir -p /app/certs && \
    chown -R codepush:nodejs /app

# Switch to non-root user
USER codepush

# Expose ports (3000 for HTTP, 8443 for HTTPS)
EXPOSE 3000 8443

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "const http = require('http'); \
    const options = { \
        host: 'localhost', \
        port: process.env.API_PORT || process.env.PORT || (process.env.HTTPS ? 8443 : 3000), \
        timeout: 2000 \
    }; \
    const request = http.request(options, (res) => { \
        console.log('Health check passed'); \
        process.exit(0); \
    }); \
    request.on('error', (err) => { \
        console.log('Health check failed'); \
        process.exit(1); \
    }); \
    request.end();"

# Start the application
CMD ["npm", "start"]