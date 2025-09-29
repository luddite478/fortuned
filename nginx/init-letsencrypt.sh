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
    
    # Wait a moment and check if nginx is still running
    sleep 2
    if kill -0 $nginx_pid 2>/dev/null; then
        echo "✅ Nginx started with PID $nginx_pid"
    else
        echo "❌ Nginx failed to start"
        cat /var/log/nginx/error.log 2>/dev/null || echo "No error log found"
        exit 1
    fi
}

# Function to reload nginx
reload_nginx() {
    echo "Reloading nginx configuration..."
    nginx -s reload
    echo "✅ Nginx configuration reloaded"
}

# Function to request certificate from Let's Encrypt
request_certificate() {
    echo "Requesting Let's Encrypt certificate for $SERVER_HOST..."
    
    # Delete dummy certificate
    delete_dummy_certificate
    
    # Request certificate
    if certbot certonly --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" --agree-tos --no-eff-email \
        --force-renewal -d "$SERVER_HOST"; then
        echo "✅ Let's Encrypt certificate obtained for $SERVER_HOST"
        return 0
    else
        echo "❌ Certificate request failed"
        if [ -f "/var/log/letsencrypt/letsencrypt.log" ]; then
            echo "Recent log entries:"
            tail -10 /var/log/letsencrypt/letsencrypt.log
        fi
        # Create dummy certificate to allow nginx to continue
        create_dummy_certificate
        return 1
    fi
}

# Function to setup certificates
setup_certificates() {
    echo "Starting certificate validation process..."
    
    # Check if we have a valid certificate (this handles container restarts)
    if validate_certificate; then
        echo "✅ Using existing valid certificate"
        return 0  # No new certificate needed
    else
        if [ "$ENV" = "stage" ]; then
            echo "Creating self-signed certificate for staging"
        else
            echo "Will obtain new Let's Encrypt certificate"
        fi
        # Create self-signed certificate for nginx to start
        create_dummy_certificate || true
        return 1  # New certificate needed
    fi
}

# Function to handle certificate request flow
handle_certificate_request() {
    if [ "$ENV" = "stage" ]; then
        echo "✅ Staging setup complete"
    else
        echo "Waiting for nginx to start..."
        sleep 5
        
        if request_certificate; then
            reload_nginx
            echo "✅ Production certificate setup complete"
        else
            echo "⚠️ Certificate request failed, continuing with dummy certificate"
        fi
    fi
}

# Function to show final status
show_final_status() {
    echo "================================================"
    echo "SSL Certificate status: READY"
    if [ "$ENV" = "stage" ]; then
        echo "Nginx running with self-signed certificate"
    else
        echo "Nginx running and serving HTTPS traffic"
    fi
    echo "================================================"
}

# Function to run the main application
run_main() {
    echo "Starting SSL certificate setup..."
    
    # Setup certificates and check if new certificate is needed
    if setup_certificates; then
        needs_new_cert=0
    else
        needs_new_cert=1
    fi
    
    # Start nginx (works with either existing cert or dummy cert)
    start_nginx
    
    # If we need a new certificate, request it
    if [ "$needs_new_cert" = 1 ]; then
        handle_certificate_request
    fi
    
    # Show final status
    show_final_status
    
    # Keep the script running
    wait $nginx_pid
}

# Main execution
run_main 