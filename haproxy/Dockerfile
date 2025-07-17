FROM haproxy:alpine

# Switch to root to install packages
USER root

# Install OpenSSL for certificate generation
RUN apk add --no-cache openssl

# Copy the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch back to haproxy user
USER haproxy

# Use our custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"] 