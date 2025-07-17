#!/bin/bash

set -e

echo "Starting certificate renewal process..."

# Renew certificates
certbot renew --quiet

# Reload nginx if certificates were renewed
nginx -s reload

echo "Certificate renewal completed successfully" 