FROM alpine:latest AS cert-builder

RUN apk add --no-cache openssl

# Generate temporary self-signed certificate
RUN openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/temp-key.pem \
    -out /tmp/temp-cert.pem \
    -days 365 -nodes \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=localhost"

# Combine certificate and key for HAProxy
RUN cat /tmp/temp-cert.pem /tmp/temp-key.pem > /tmp/haproxy.pem

FROM haproxy:alpine

COPY --from=cert-builder /tmp/haproxy.pem /usr/local/etc/haproxy/certs/haproxy.pem
