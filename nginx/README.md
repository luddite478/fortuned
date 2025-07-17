# Nginx + Let's Encrypt Setup

This setup uses nginx with automatic Let's Encrypt certificate generation and renewal, based on the nginx-certbot pattern.

## Setup Instructions

1. **Configure domain and email**:
   ```bash
   # Edit nginx/.env and set your domain and email
   nano nginx/.env
   ```

2. **Start the services**:
   ```bash
   # Start all services
   docker compose up -d
   ```

## How it works

1. **Initial startup**: 
   - Nginx starts with a dummy self-signed certificate
   - Once nginx is running, the script requests a real Let's Encrypt certificate
   - Nginx is reloaded with the real certificate

2. **Certificate renewal**:
   - Certificates are automatically renewed by certbot
   - The renewal script can be run manually: `nginx/renew-certificates.sh`

3. **Routing**:
   - HTTP (port 80): Serves Let's Encrypt challenges, redirects to HTTPS
   - HTTPS (port 443): Serves your application
   - WebSocket support: `/ws` endpoint routes to websocket backend
   - API endpoints: All other routes go to the API backend

## Directory Structure

- `nginx/nginx.conf`: Main nginx configuration
- `nginx/templates/app.conf.template`: Server configuration template
- `nginx/init-letsencrypt.sh`: Initialization script
- `nginx/renew-certificates.sh`: Certificate renewal script
- `letsencrypt/`: Let's Encrypt certificates storage
- `certbot-webroot/`: Webroot for ACME challenges

## Environment Variables

- `DOMAIN`: Your domain name (e.g., example.com)
- `EMAIL`: Email for Let's Encrypt registration (e.g., admin@example.com)

## Backends

The configuration routes to these backends:
- API: `server:8888`
- WebSocket: `server:8765`

Update the upstream configuration in `nginx/templates/app.conf.template` if your backend ports are different. 