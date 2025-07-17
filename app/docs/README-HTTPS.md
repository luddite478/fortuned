# HTTPS Setup for NIYYA Server

This guide explains how to set up HTTPS for your NIYYA server using HAProxy and Let's Encrypt certificates.

## Prerequisites

- A domain name pointing to your server (e.g., `myapp.example.com`)
- Docker and docker-compose installed
- Port 80 and 443 accessible from the internet

## Quick Setup

### 1. Configure Environment

Copy the example environment file and update it with your domain:

```bash
cp env.example .env
```

Edit `.env` and set your domain:

```bash
# Required: Replace with your actual domain
DOMAIN=myapp.example.com
SERVER_HOST=myapp.example.com
WEBSOCKET_HOST=myapp.example.com
WEBSOCKET_PORT=443

# Generate a secure API token
API_TOKEN=your_secure_random_token_here
```

### 2. Generate SSL Certificate

Run the certificate generation script:

```bash
./generate-cert.sh
```

This script will:
- Create necessary directories
- Stop any conflicting services
- Generate a Let's Encrypt certificate
- Prepare the certificate for HAProxy
- Provide next steps

### 3. Start Services

Once the certificate is generated, start all services:

```bash
docker-compose up -d
```

Your server will now be available at:
- **HTTPS API**: `https://myapp.example.com/api/v1/`
- **WSS WebSocket**: `wss://myapp.example.com`

## Architecture

```
Internet → HAProxy (Port 443) → Backend Services
              ↓
         [SSL Termination]
              ↓
    ┌─────────────────┬──────────────────┐
    │   API Backend   │  WebSocket       │
    │   (Port 8888)   │  Backend         │
    │                 │  (Port 8765)     │
    └─────────────────┴──────────────────┘
```

## Certificate Management

### Auto-Renewal

Set up a cron job to automatically renew certificates:

```bash
# Add to crontab (crontab -e)
0 2 * * 0 /path/to/your/server/renew-cert.sh >> /var/log/cert-renewal.log 2>&1
```

### Manual Renewal

To manually renew certificates:

```bash
./renew-cert.sh
```

## Troubleshooting

### Certificate Generation Issues

1. **Domain not pointing to server**:
   ```bash
   # Test DNS resolution
   nslookup myapp.example.com
   ```

2. **Port 80 blocked**:
   ```bash
   # Check if port 80 is accessible
   sudo netstat -tlnp | grep :80
   ```

3. **Firewall issues**:
   ```bash
   # Make sure ports 80 and 443 are open
   sudo ufw allow 80
   sudo ufw allow 443
   ```

### Service Issues

1. **Check container logs**:
   ```bash
   docker-compose logs haproxy
   docker-compose logs server
   ```

2. **Test HAProxy configuration**:
   ```bash
   docker run --rm -v $(pwd)/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro haproxy:alpine haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg
   ```

3. **Verify certificate**:
   ```bash
   openssl x509 -in certs/haproxy.pem -text -noout
   ```

### Client Connection Issues

1. **Flutter app can't connect**:
   - Verify your `.env` file has the correct domain
   - Check that `SERVER_HOST` matches your domain
   - Ensure `WEBSOCKET_HOST` is set to your domain
   - Confirm `WEBSOCKET_PORT` is set to `443`

2. **WebSocket connection fails**:
   ```bash
   # Test WebSocket connectivity
   wscat -c wss://myapp.example.com
   ```

## Development vs Production

### Development (localhost)
```bash
SERVER_HOST=localhost
WEBSOCKET_HOST=localhost
WEBSOCKET_PORT=8765
```
- Uses HTTP and WS (no encryption)
- Direct connection to services

### Production (your domain)
```bash
SERVER_HOST=myapp.example.com
WEBSOCKET_HOST=myapp.example.com
WEBSOCKET_PORT=443
```
- Uses HTTPS and WSS (encrypted)
- Routes through HAProxy

## Security Features

- **TLS 1.2+ only**: Modern encryption standards
- **HSTS**: HTTP Strict Transport Security headers
- **Security headers**: X-Frame-Options, X-Content-Type-Options, etc.
- **Automatic HTTP→HTTPS redirect**: All HTTP traffic redirected to HTTPS

## File Structure

```
server/
├── docker-compose.yaml    # Updated with HAProxy and certbot
├── haproxy.cfg           # HAProxy configuration
├── generate-cert.sh      # Certificate generation script
├── renew-cert.sh         # Certificate renewal script
├── .env                  # Your configuration (copy from env.example)
├── certs/                # Generated certificates (created automatically)
│   └── haproxy.pem      # Combined certificate for HAProxy
└── letsencrypt/          # Let's Encrypt data (created automatically)
    └── live/
        └── yourdomain.com/
            ├── fullchain.pem
            └── privkey.pem
```

## Support

If you encounter issues:
1. Check the logs: `docker-compose logs`
2. Verify your domain DNS settings
3. Ensure firewall allows ports 80 and 443
4. Test certificate validity

For additional help, please check the main project documentation. 