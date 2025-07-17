#!/bin/sh

while :; do
  if [ ! -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem ]; then
    echo "Generating certificate for $DOMAIN..."
    certbot certonly --standalone --agree-tos --no-eff-email --email admin@$DOMAIN -d $DOMAIN --non-interactive --keep-until-expiring
    if [ $? -eq 0 ]; then
      cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem > /certs/haproxy.pem
      echo "Certificate created successfully"
    fi
  else
    echo "Certificate already exists, checking for renewal..."
    certbot renew --quiet
    if [ $? -eq 0 ]; then
      cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem > /certs/haproxy.pem
      echo "Certificate renewed successfully"
    fi
  fi
  sleep 12h
done 