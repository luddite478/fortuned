#!/bin/bash

set -e

# Check if SERVER_HOST is set
if [ -z "$SERVER_HOST" ]; then
    echo "Error: SERVER_HOST environment variable is not set"
    exit 1
fi

# Check if email is set
if [ -z "$EMAIL" ]; then
    echo "Error: EMAIL environment variable is not set"
    exit 1
fi

# Set environment (default to prod if not set)
if [ -z "$ENV" ]; then
    ENV=prod
fi

data_path="/etc/letsencrypt"
rsa_key_size=4096
domain_path="$data_path/live/$SERVER_HOST"

echo "================================================"
echo "Let's Encrypt SSL Certificate Manager"
echo "Host: $SERVER_HOST"
echo "Certificate path: $domain_path"
if [ "$ENV" = "stage" ]; then
    echo "Mode: STAGING (test certificates)"
else
    echo "Mode: PRODUCTION (trusted certificates)"
fi
echo "================================================"

# Function to validate existing certificate
validate_certificate() {
    local cert_path="$domain_path/fullchain.pem"
    local key_path="$domain_path/privkey.pem"
    
    echo "Checking for existing certificate..."
    
    # Check if certificate files exist
    if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        echo "❌ Certificate files do not exist"
        return 1
    fi
    
    echo "✅ Certificate files found"
    
    # Check if certificate is valid (not expired and expires in more than 30 days)
    if ! openssl x509 -in "$cert_path" -checkend 2592000 -noout > /dev/null 2>&1; then
        echo "❌ Certificate is expired or expires within 30 days"
        return 1
    fi
    
    echo "✅ Certificate is valid and has more than 30 days remaining"
    
    # Check if certificate is for the correct domain
    if ! openssl x509 -in "$cert_path" -text -noout | grep -q "DNS:$SERVER_HOST"; then
        echo "❌ Certificate is not for domain $SERVER_HOST"
        return 1
    fi
    
    echo "✅ Certificate is for the correct domain: $SERVER_HOST"
    
    # Check if certificate is issued by Let's Encrypt
    if openssl x509 -in "$cert_path" -text -noout | grep -q "Issuer:.*Let's Encrypt"; then
        # Get certificate expiration date for logging
        local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        if [ "$ENV" = "stage" ]; then
            echo "✅ Valid Let's Encrypt STAGING certificate found"
        else
            echo "✅ Valid Let's Encrypt PRODUCTION certificate found"
        fi
        echo "   Expires: $expiry_date"
        return 0
    else
        echo "❌ Certificate exists but is not issued by Let's Encrypt (likely dummy certificate)"
        return 1
    fi
}

# Function to create dummy certificate
create_dummy_certificate() {
    echo "Creating temporary dummy certificate for $SERVER_HOST..."
    
    mkdir -p "$domain_path"
    
    # Generate dummy certificate
    openssl req -x509 -newkey rsa:$rsa_key_size -keyout "$domain_path/privkey.pem" \
        -out "$domain_path/fullchain.pem" -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$SERVER_HOST"
    
    echo "✅ Temporary dummy certificate created (will be replaced with real certificate)"
}

# Function to delete dummy certificate
delete_dummy_certificate() {
    echo "Removing temporary dummy certificate..."
    rm -rf "$domain_path"
    echo "✅ Temporary dummy certificate removed"
}

# Function to start nginx
start_nginx() {
    echo "Starting nginx..."
    
    # Process template and create final config
    envsubst '${SERVER_HOST}' < /etc/nginx/templates/app.conf.template > /etc/nginx/conf.d/app.conf
    
    # Test nginx configuration
    nginx -t
    
    # Start nginx
    nginx -g "daemon off;" &
    nginx_pid=$!
    
    echo "✅ Nginx started with PID $nginx_pid"
}

# Function to reload nginx
reload_nginx() {
    echo "Reloading nginx configuration..."
    nginx -s reload
    echo "✅ Nginx configuration reloaded"
}

# Function to request certificate
request_certificate() {
    echo "ENV - $ENV"
    if [ "$ENV" = "stage" ]; then
        echo "Requesting Let's Encrypt STAGING certificate for $SERVER_HOST..."
        staging_flag="--staging"
    else
        echo "Requesting Let's Encrypt PRODUCTION certificate for $SERVER_HOST..."
        staging_flag=""
    fi
    
    # Delete dummy certificate
    delete_dummy_certificate
    
    # Request certificate
    certbot certonly --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" --agree-tos --no-eff-email \
        --force-renewal $staging_flag -d "$SERVER_HOST"
    
    if [ "$ENV" = "stage" ]; then
        echo "✅ Let's Encrypt STAGING certificate obtained for $SERVER_HOST"
        echo "   Note: This is a test certificate and will show as untrusted in browsers"
    else
        echo "✅ Let's Encrypt PRODUCTION certificate obtained for $SERVER_HOST"
    fi
}

# Main logic
echo "Starting certificate validation process..."

# Check if we have a valid certificate (this handles container restarts)
if validate_certificate; then
    echo ""
    echo "🎉 CONTAINER RESTART DETECTED: Using existing valid certificate"
    echo "   No new certificate needed - skipping certificate request"
    echo ""
    needs_new_cert=false
else
    echo ""
    echo "🔄 NEW SETUP OR INVALID CERTIFICATE: Will obtain new certificate"
    echo ""
    needs_new_cert=true
    # Create dummy certificate for nginx to start
    create_dummy_certificate
fi

# Start nginx (works with either existing cert or dummy cert)
start_nginx

# If we need a new certificate, request it
if [ "$needs_new_cert" = true ]; then
    echo "Waiting for nginx to fully start..."
    sleep 5
    echo "Requesting new certificate from Let's Encrypt..."
    request_certificate
    reload_nginx
    echo ""
    if [ "$ENV" = "stage" ]; then
        echo "🎉 STAGING CERTIFICATE SETUP COMPLETE"
    else
        echo "🎉 PRODUCTION CERTIFICATE SETUP COMPLETE"
    fi
else
    echo ""
    echo "🎉 USING EXISTING CERTIFICATE - READY TO SERVE TRAFFIC"
fi

echo ""
echo "================================================"
echo "SSL Certificate status: READY"
if [ "$ENV" = "stage" ]; then
    echo "Nginx is running with STAGING certificate"
    echo "Note: Browsers will show security warnings for staging certificates"
else
    echo "Nginx is running and serving HTTPS traffic"
fi
echo "================================================"

# Keep the script running
wait $nginx_pid 