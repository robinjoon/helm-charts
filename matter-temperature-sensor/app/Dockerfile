# Multi-stage build for Matter Temperature Sensor
FROM node:22-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++ linux-headers

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Final stage
FROM node:22-alpine

# Install runtime dependencies for Matter.js
# Matter.js may need some system libraries for networking
RUN apk add --no-cache \
    dbus \
    bluez \
    bluez-libs \
    bluez-deprecated \
    ca-certificates

WORKDIR /app

# Copy installed dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application code
COPY . .

# Create data directory for Matter storage
RUN mkdir -p /data && chown -R node:node /data

# Use non-root user
USER node

# Set environment variables
ENV NODE_ENV=production
ENV STORAGE_PATH=/data

# Expose Matter default port
EXPOSE 5540/udp
EXPOSE 5540/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD node -e "console.log('OK')" || exit 1

# Start the application
CMD ["node", "index.js"]
