FROM alpine:3.22

RUN apk add --no-cache nginx openssl gettext

# gettext provides envsubst, used at startup to inject DOMAIN_NAME into the config
RUN mkdir -p /etc/nginx/ssl

# Remove the default port-80 server block shipped with Alpine's nginx
RUN rm -f /etc/nginx/http.d/default.conf

COPY conf/wordpress.conf.template /etc/nginx/http.d/wordpress.conf.template
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 443

ENTRYPOINT ["/entrypoint.sh"]
