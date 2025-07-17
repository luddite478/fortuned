#!/bin/bash

# Certificate renewal script for NIYYA server
# This script renews SSL certificates and restarts services if needed

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Check if DOMAIN is set
if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN environment variable is not set"
    echo "Please set DOMAIN in your .env file (e.g., DOMAIN=myapp.example.com)"
    exit 1
fi

echo "🔄 Renewing SSL certificate for domain: $DOMAIN"

# Renew certificate
docker run --rm \
    -v $(pwd)/letsencrypt:/etc/letsencrypt \
    -v $(pwd)/certs:/certs \
    certbot/certbot renew --quiet

# Check if renewal was successful
if [ $? -eq 0 ]; then
    echo "📜 Updating HAProxy certificate..."
    
    # Combine certificate and private key for HAProxy
    cat "letsencrypt/live/$DOMAIN/fullchain.pem" "letsencrypt/live/$DOMAIN/privkey.pem" > "certs/haproxy.pem"
    
    # Set appropriate permissions
    chmod 600 certs/haproxy.pem
    
    echo "🔄 Restarting HAProxy to load new certificate..."
    docker-compose restart haproxy
    
    echo "✅ Certificate renewal completed successfully!"
else
    echo "ℹ️  Certificate renewal not needed or failed"
fi 