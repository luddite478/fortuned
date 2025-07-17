# NIYYA Server HTTPS Setup

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

## Notes

- Make sure your domain points to your server
- Ports 80 and 443 must be open
- First certificate generation may take a few minutes
