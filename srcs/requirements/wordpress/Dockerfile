FROM alpine:3.22

# Mandatory PHP extensions — required for WordPress core + WP-CLI
RUN apk add --no-cache \
    php84 \
    php84-fpm \
    php84-mysqli \
    php84-pdo \
    php84-pdo_mysql \
    php84-gd \
    php84-curl \
    php84-mbstring \
    php84-xml \
    php84-zip \
    php84-opcache \
    php84-session \
    php84-intl \
    php84-fileinfo \
    php84-phar \
    wget \
    mariadb-client

# Bonus-only PHP extensions — redis-cache plugin + wp config set for Redis
# Installed only when BONUS=true (injected by make bonus via docker-compose build arg)
ARG BONUS=false
RUN if [ "${BONUS}" = "true" ]; then \
    apk add --no-cache php84-redis php84-ctype php84-tokenizer; \
fi

# WP-CLI needs a plain 'php' binary in PATH
RUN ln -s /usr/bin/php84 /usr/bin/php

# Install WP-CLI
RUN wget -q https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -O /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

RUN echo "memory_limit = 256M" > /etc/php84/conf.d/memory.ini

RUN mkdir -p /var/www/html

COPY conf/www.conf /etc/php84/php-fpm.d/www.conf
COPY tools/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9000

# Healthy when php-fpm is actually accepting connections on port 9000.
# --start-period gives the entrypoint time to run WP install / bonus setup
# before health failures count against the retry limit.
HEALTHCHECK --interval=5s --timeout=3s --start-period=120s --retries=3 \
    CMD nc -z 127.0.0.1 9000 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
