#!/bin/sh
set -e

SSL_DIR="/etc/nginx/ssl"

# Inject DOMAIN_NAME and DOMAIN_ROOT into the nginx config.
# The explicit variable list prevents envsubst from replacing nginx
# variables like $uri, $args, $document_root, etc.
envsubst '${DOMAIN_NAME} ${DOMAIN_ROOT}' \
    < /etc/nginx/http.d/wordpress.conf.template \
    > /etc/nginx/http.d/wordpress.conf

# Generate a self-signed TLS certificate if one doesn't exist yet
if [ ! -f "${SSL_DIR}/nginx.crt" ]; then
    echo "Generating self-signed TLS certificate for ${DOMAIN_NAME}..."
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "${SSL_DIR}/nginx.key" \
        -out    "${SSL_DIR}/nginx.crt" \
        -subj   "/C=FR/ST=IDF/L=Paris/O=42/CN=${DOMAIN_NAME}"
fi

exec nginx -g "daemon off;"
