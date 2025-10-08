# Fortuned Server HTTPS Setup

Simple HTTPS setup with HAProxy and Let's Encrypt.

## Setup

1. **Configure your domain**:
   ```bash
   cp env.example .env
   # Edit .env and set DOMAIN=yourdomain.com
   ```

2. **Start everything**:
   ```bash
   docker-compose up -d
   ```

That's it! The setup will:
- Generate SSL certificates automatically
- Renew them every 12 hours
- Route HTTP to HTTPS
- Handle WebSocket connections (WSS)

## Access

- **API**: `https://yourdomain.com/api/v1/`
- **WebSocket**: `wss://yourdomain.com`

## Logs

Check if everything is working:
```bash
docker-compose logs haproxy
docker-compose logs certbot
```

## Environment Configuration

The server supports two environments via the `ENV` variable:

### Production Environment (`ENV=prod`)
- Normal startup behavior
- Database initialization without dropping existing data

### Stage Environment (`ENV=stage`)
- Automatically drops and reinitializes database on startup
- Cleans up S3 folder specified in `S3_FOLDER` (defaults to `stage/`)
- Useful for testing with a clean slate

Configure in your `.env` file:
```bash
ENV=stage
S3_FOLDER=stage/  # Optional, defaults to stage/
```

## Notes

- Make sure your domain points to your server
- Ports 80 and 443 must be open
- First certificate generation may take a few minutes
- **Warning**: Setting `ENV=stage` will delete all database data and S3 files in the configured folder on startup
