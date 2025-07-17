FROM haproxy:alpine

# Install OpenSSL for certificate generation
RUN apk add --no-cache openssl

# Copy the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Use our custom entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"] 