FROM nginx:alpine

# Install certbot and openssl
RUN apk add --no-cache certbot openssl bash

# Create directory for certbot webroot
RUN mkdir -p /var/www/certbot

# Copy nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY templates/ /etc/nginx/templates/

# Copy and make executable the initialization script
COPY init-letsencrypt.sh /usr/local/bin/init-letsencrypt.sh
RUN chmod +x /usr/local/bin/init-letsencrypt.sh

# Create directories for certificates
RUN mkdir -p /etc/letsencrypt

# Use our initialization script as entrypoint
ENTRYPOINT ["/usr/local/bin/init-letsencrypt.sh"] 