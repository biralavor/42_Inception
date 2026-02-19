# NGINX service Dockerfile
# Target path: srcs/requirements/nginx/Dockerfile
# Base: Alpine penultimate stable (3.20)
FROM alpine:oldstable

LABEL maintainer="umeneses <umeneses@student.42sp.org.br>"
LABEL description="NGINX with TLSv1.2/TLSv1.3 for Inception"

RUN apk update && apk add --no-cache \
    nginx \
    openssl

# Runtime directories
RUN mkdir -p /etc/nginx/ssl /var/www/html /run/nginx

# Self-signed TLS certificate (replace with real cert in production)
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out    /etc/nginx/ssl/nginx.crt \
    -subj   "/C=BR/ST=SP/L=SaoPaulo/O=42/CN=umeneses.42.fr"

# Inline nginx config — no external COPY dependency for first build
RUN printf 'events {}\n\
http {\n\
    include       /etc/nginx/mime.types;\n\
    default_type  application/octet-stream;\n\
\n\
    server {\n\
        listen 443 ssl;\n\
        server_name umeneses.42.fr;\n\
\n\
        ssl_certificate     /etc/nginx/ssl/nginx.crt;\n\
        ssl_certificate_key /etc/nginx/ssl/nginx.key;\n\
        ssl_protocols       TLSv1.2 TLSv1.3;\n\
        ssl_ciphers         HIGH:!aNULL:!MD5;\n\
\n\
        root  /var/www/html;\n\
        index index.php index.html;\n\
\n\
        location / {\n\
            try_files $uri $uri/ /index.php?$args;\n\
        }\n\
\n\
        location ~ \\.php$ {\n\
            fastcgi_pass  wordpress:9000;\n\
            fastcgi_index index.php;\n\
            include       fastcgi_params;\n\
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\n\
        }\n\
    }\n\
}\n' > /etc/nginx/nginx.conf

EXPOSE 443

# PID 1: nginx in foreground — no daemon, no sleep infinity, no tail -f
CMD ["nginx", "-g", "daemon off;"]
