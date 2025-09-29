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
    echo "Processing nginx template..."
    envsubst '${SERVER_HOST},${HTTP_API_PORT},${HTTPS_API_PORT},${WEBSOCKET_PORT}' < /etc/nginx/templates/app.conf.template > /etc/nginx/conf.d/app.conf
    
    echo "Generated nginx config:"
    cat /etc/nginx/conf.d/app.conf
    
    # Test nginx configuration
    echo "Testing nginx configuration..."
    if nginx -t; then
        echo "✅ Nginx configuration is valid"
    else
        echo "❌ Nginx configuration test failed!"
        echo "Config file contents:"
        cat /etc/nginx/conf.d/app.conf
        exit 1
    fi
    
    # Start nginx
    echo "Starting nginx daemon..."
    nginx -g "daemon off;" &
    nginx_pid=$!
    
    # Wait a moment and check if nginx is still running
    sleep 2
    if kill -0 $nginx_pid 2>/dev/null; then
        echo "✅ Nginx started successfully with PID $nginx_pid"
    else
        echo "❌ Nginx failed to start or crashed immediately!"
        echo "Checking nginx error logs..."
        cat /var/log/nginx/error.log || echo "No error log found"
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
    echo "Requesting Let's Encrypt PRODUCTION certificate for $SERVER_HOST..."
    
    # Delete dummy certificate
    delete_dummy_certificate
    
    # Request certificate with detailed error logging
    echo "Running certbot command with verbose output..."
    echo "Command: certbot certonly --webroot --webroot-path=/var/www/certbot --email $EMAIL --agree-tos --no-eff-email --force-renewal -d $SERVER_HOST"
    
    if certbot certonly --webroot --webroot-path=/var/www/certbot \
        --email "$EMAIL" --agree-tos --no-eff-email \
        --force-renewal -d "$SERVER_HOST" --verbose 2>&1; then
        echo "✅ Let's Encrypt PRODUCTION certificate obtained for $SERVER_HOST"
        return 0
    else
        local exit_code=$?
        echo ""
        echo "❌ CERTIFICATE REQUEST FAILED!"
        echo "Exit code: $exit_code"
        echo ""
        echo "🔍 TROUBLESHOOTING INFORMATION:"
        echo "1. Check if domain resolves correctly:"
        echo "   dig $SERVER_HOST"
        echo ""
        echo "2. Test ACME challenge accessibility:"
        echo "   curl -I http://$SERVER_HOST/.well-known/acme-challenge/"
        echo ""
        echo "3. Check certbot logs:"
        echo "   ls -la /var/log/letsencrypt/"
        echo "   cat /var/log/letsencrypt/letsencrypt.log"
        echo ""
        echo "4. Common issues:"
        echo "   - Domain not pointing to this server"
        echo "   - Port 80 not accessible from internet"
        echo "   - Rate limiting (5 failures per hour, 50 certificates per week)"
        echo "   - Firewall blocking Let's Encrypt servers"
        echo ""
        
        # Show recent log entries if available
        if [ -f "/var/log/letsencrypt/letsencrypt.log" ]; then
            echo "📋 RECENT CERTBOT LOG ENTRIES:"
            tail -20 /var/log/letsencrypt/letsencrypt.log
            echo ""
        fi
        
        # Create dummy certificate to allow nginx to continue
        echo "Creating dummy certificate to allow nginx to continue..."
        create_dummy_certificate
        
        return $exit_code
    fi
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
        
        if request_certificate; then
            reload_nginx
            echo ""
            echo "🎉 PRODUCTION CERTIFICATE SETUP COMPLETE"
        else
            echo ""
            echo "⚠️  PRODUCTION CERTIFICATE REQUEST FAILED"
            echo "   Continuing with dummy certificate for now"
            echo "   Check the error messages above and troubleshoot"
            echo "   Nginx will still serve HTTPS but with self-signed certificate"
        fi
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
    echo "🚀 STARTING CERTIFICATE SETUP PROCESS"
    echo "Timestamp: $(date)"
    echo "PID: $$"
    echo ""
    
    # Setup certificates and check if new certificate is needed
    setup_certificates
    needs_new_cert=$?
    
    # Start nginx (works with either existing cert or dummy cert)
    start_nginx
    
    # If we need a new certificate, request it
    if [ "$needs_new_cert" = 1 ]; then
        echo "📋 Certificate needed - proceeding with Let's Encrypt request"
        handle_certificate_request
    else
        echo ""
        echo "🎉 USING EXISTING CERTIFICATE - READY TO SERVE TRAFFIC"
    fi
    
    # Show final status
    show_final_status
    
    echo "🔄 ENTERING NGINX WAIT LOOP"
    echo "Nginx PID: $nginx_pid"
    echo "Script will now keep nginx running..."
    
    # Keep the script running and monitor nginx
    while true; do
        if ! kill -0 $nginx_pid 2>/dev/null; then
            echo "❌ Nginx process died! PID $nginx_pid no longer exists"
            echo "Checking error logs..."
            cat /var/log/nginx/error.log || echo "No error log found"
            exit 1
        fi
        sleep 30
    done
}

# Main execution
run_main 