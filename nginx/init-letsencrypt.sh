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

# Check if HTTP_API_PORT is set
if [ -z "$HTTP_API_PORT" ]; then
    echo "Error: HTTP_API_PORT environment variable is not set"
    exit 1
fi

# Check if HTTPS_API_PORT is set
if [ -z "$HTTPS_API_PORT" ]; then
    echo "Error: HTTPS_API_PORT environment variable is not set"
    exit 1
fi

# Check if WEBSOCKET_PORT is set
if [ -z "$WEBSOCKET_PORT" ]; then
    echo "Error: WEBSOCKET_PORT environment variable is not set"
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
    
    # For staging, accept self-signed certificates
    if [ "$ENV" = "stage" ]; then
        # Get certificate expiration date for logging
        local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
        echo "✅ Valid SELF-SIGNED certificate found for staging"
        echo "   Expires: $expiry_date"
        return 0
    else
        # For production, check if certificate is issued by Let's Encrypt
        if openssl x509 -in "$cert_path" -text -noout | grep -q "Issuer:.*Let's Encrypt"; then
            # Get certificate expiration date for logging
            local expiry_date=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)
            echo "✅ Valid Let's Encrypt PRODUCTION certificate found"
            echo "   Expires: $expiry_date"
            return 0
        else
            echo "❌ Certificate exists but is not issued by Let's Encrypt (likely dummy certificate)"
            return 1
        fi
    fi
}

# Function to create self-signed certificate
create_dummy_certificate() {
    if [ "$ENV" = "stage" ]; then
        echo "Creating self-signed certificate for $SERVER_HOST (staging mode)..."
        cert_purpose="staging environment"
    else
        echo "Creating temporary dummy certificate for $SERVER_HOST..."
        cert_purpose="temporary use (will be replaced with real certificate)"
    fi
    
    mkdir -p "$domain_path"
    
    # Generate self-signed certificate
    openssl req -x509 -newkey rsa:$rsa_key_size -keyout "$domain_path/privkey.pem" \
        -out "$domain_path/fullchain.pem" -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$SERVER_HOST" \
        -addext "subjectAltName=DNS:$SERVER_HOST,DNS:localhost"
    
    echo "✅ Self-signed certificate created for $cert_purpose"
    if [ "$ENV" = "stage" ]; then
        echo "   Valid for: 365 days"
        echo "   Note: This certificate will show as untrusted in browsers (expected for staging)"
    fi
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
    envsubst '${SERVER_HOST},${HTTP_API_PORT},${HTTPS_API_PORT},${WEBSOCKET_PORT}' < /etc/nginx/templates/app.conf.template > /etc/nginx/conf.d/app.conf
    
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

# Function to request certificate from Let's Encrypt
request_certificate() {
    echo "Requesting Let's Encrypt PRODUCTION certificate for $SERVER_HOST..."
    
    # Delete dummy certificate
    delete_dummy_certificate
    
    # Request certificate
    certbot certonly --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" --agree-tos --no-eff-email \
        --force-renewal -d "$SERVER_HOST"
    
    echo "✅ Let's Encrypt PRODUCTION certificate obtained for $SERVER_HOST"
}

# Function to setup certificates
setup_certificates() {
    echo "Starting certificate validation process..."
    
    # Check if we have a valid certificate (this handles container restarts)
    if validate_certificate; then
        echo ""
        echo "🎉 CONTAINER RESTART DETECTED: Using existing valid certificate"
        echo "   No new certificate needed - skipping certificate request"
        echo ""
        return 0  # No new certificate needed
    else
        echo ""
        if [ "$ENV" = "stage" ]; then
            echo "🔄 NEW SETUP OR INVALID CERTIFICATE: Will create self-signed certificate"
        else
            echo "🔄 NEW SETUP OR INVALID CERTIFICATE: Will obtain new certificate"
        fi
        echo ""
        # Create self-signed certificate for nginx to start
        create_dummy_certificate
        return 1  # New certificate needed
    fi
}

# Function to handle certificate request flow
handle_certificate_request() {
    if [ "$ENV" = "stage" ]; then
        echo ""
        echo "🎉 STAGING SELF-SIGNED CERTIFICATE SETUP COMPLETE"
        echo "   Self-signed certificate is already in place and ready to use"
    else
        echo "Waiting for nginx to fully start..."
        sleep 5
        request_certificate
        reload_nginx
        echo ""
        echo "🎉 PRODUCTION CERTIFICATE SETUP COMPLETE"
    fi
}

# Function to show final status
show_final_status() {
    echo ""
    echo "================================================"
    echo "SSL Certificate status: READY"
    if [ "$ENV" = "stage" ]; then
        echo "Nginx is running with SELF-SIGNED certificate"
        echo "Note: Browsers will show security warnings for self-signed certificates"
    else
        echo "Nginx is running and serving HTTPS traffic"
    fi
    echo "================================================"
}

# Function to run the main application
run_main() {
    # Setup certificates and check if new certificate is needed
    setup_certificates
    needs_new_cert=$?
    
    # Start nginx (works with either existing cert or dummy cert)
    start_nginx
    
    # If we need a new certificate, request it
    if [ "$needs_new_cert" = 1 ]; then
        handle_certificate_request
    else
        echo ""
        echo "🎉 USING EXISTING CERTIFICATE - READY TO SERVE TRAFFIC"
    fi
    
    # Show final status
    show_final_status
    
    # Keep the script running
    wait $nginx_pid
}

# Main execution
run_main 