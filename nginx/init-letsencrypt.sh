#!/bin/bash

set -e

# Check if domain is set
if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN environment variable is not set"
    exit 1
fi

# Check if email is set
if [ -z "$EMAIL" ]; then
    echo "Error: EMAIL environment variable is not set"
    exit 1
fi

data_path="/etc/letsencrypt"
rsa_key_size=4096
domain_path="$data_path/live/$DOMAIN"

# Function to create dummy certificate
create_dummy_certificate() {
    echo "Creating dummy certificate for $DOMAIN..."
    
    mkdir -p "$domain_path"
    
    # Generate dummy certificate
    openssl req -x509 -newkey rsa:$rsa_key_size -keyout "$domain_path/privkey.pem" \
        -out "$domain_path/fullchain.pem" -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$DOMAIN"
    
    echo "Dummy certificate created for $DOMAIN"
}

# Function to delete dummy certificate
delete_dummy_certificate() {
    echo "Deleting dummy certificate for $DOMAIN..."
    rm -rf "$domain_path"
    echo "Dummy certificate deleted for $DOMAIN"
}

# Function to start nginx
start_nginx() {
    echo "Starting nginx..."
    
    # Process template and create final config
    envsubst '${DOMAIN}' < /etc/nginx/templates/app.conf.template > /etc/nginx/conf.d/app.conf
    
    # Test nginx configuration
    nginx -t
    
    # Start nginx
    nginx -g "daemon off;" &
    nginx_pid=$!
    
    echo "Nginx started with PID $nginx_pid"
}

# Function to reload nginx
reload_nginx() {
    echo "Reloading nginx..."
    nginx -s reload
    echo "Nginx reloaded"
}

# Function to request certificate
request_certificate() {
    echo "Requesting Let's Encrypt certificate for $DOMAIN..."
    
    # Delete dummy certificate
    delete_dummy_certificate
    
    # Request certificate
    certbot certonly --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" --agree-tos --no-eff-email \
        --force-renewal -d "$DOMAIN"
    
    echo "Certificate obtained for $DOMAIN"
}

# Main logic
echo "Starting Let's Encrypt initialization for $DOMAIN..."

# Check if certificate already exists
if [ -f "$domain_path/fullchain.pem" ] && [ -f "$domain_path/privkey.pem" ]; then
    echo "Certificate already exists for $DOMAIN"
else
    echo "No certificate found for $DOMAIN"
    create_dummy_certificate
fi

# Start nginx
start_nginx

# If using dummy certificate, request real certificate
if openssl x509 -in "$domain_path/fullchain.pem" -text -noout | grep -q "CN=$DOMAIN"; then
    # This is likely our dummy certificate, request real one
    sleep 5  # Give nginx time to start
    request_certificate
    reload_nginx
fi

# Keep the script running
wait $nginx_pid 