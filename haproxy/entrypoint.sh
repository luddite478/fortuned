#!/bin/sh

# Create certs directory if it doesn't exist
mkdir -p /usr/local/etc/haproxy/certs

# Check if certificate exists
if [ ! -f /usr/local/etc/haproxy/certs/haproxy.pem ]; then
    echo "Generating temporary self-signed certificate..."
    
    # Generate self-signed certificate
    openssl req -x509 -newkey rsa:2048 \
        -keyout /tmp/temp-key.pem \
        -out /tmp/temp-cert.pem \
        -days 365 -nodes \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"
    
    # Combine certificate and key for HAProxy
    cat /tmp/temp-cert.pem /tmp/temp-key.pem > /usr/local/etc/haproxy/certs/haproxy.pem
    
    # Clean up temporary files
    rm -f /tmp/temp-cert.pem /tmp/temp-key.pem
    
    echo "Temporary certificate generated successfully"
else
    echo "Certificate already exists, using existing certificate"
fi

# Start HAProxy
echo "Starting HAProxy..."
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg 