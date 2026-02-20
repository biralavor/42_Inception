#!/bin/sh
set -e

# Read DB password from Docker secret
DB_PASSWORD=$(cat /run/secrets/db_password)

# Read WP credentials from Docker secret (one value per line):
#   Line 1 - admin login     (must NOT be 'admin', 'Admin', 'administrator')
#   Line 2 - admin password
#   Line 3 - regular user login
#   Line 4 - regular user password
WP_ADMIN_USER=$(sed -n '1p' /run/secrets/credentials)
WP_ADMIN_PASS=$(sed -n '2p' /run/secrets/credentials)
WP_USER=$(sed -n '3p' /run/secrets/credentials)
WP_USER_PASS=$(sed -n '4p' /run/secrets/credentials)

# Non-sensitive config from environment (.env)
DB_NAME="${WP_DATABASE:-wordpress}"
DB_USER="${WP_USER:-wp_user}"
DB_HOST="${WP_HOST:-mariadb}"
DOMAIN="${DOMAIN_NAME:-localhost}"
WP_PATH="${DOMAIN_ROOT:-/var/www/html}"

# Wait for MariaDB to accept connections (bounded: 30 attempts)
echo "Waiting for MariaDB at ${DB_HOST}..."
i=0
until mysqladmin ping -h "${DB_HOST}" --silent 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 30 ] && echo "ERROR: MariaDB not reachable after 30s" && exit 1
    sleep 1
done
echo "MariaDB is ready."

if [ ! -f "${WP_PATH}/wp-config.php" ]; then
    echo "Installing WordPress..."

    wp core download \
        --path="${WP_PATH}" \
        --allow-root

    wp config create \
        --path="${WP_PATH}" \
        --dbname="${DB_NAME}" \
        --dbuser="${DB_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${DB_HOST}" \
        --dbprefix="${WP_TABLE_PREFIX:-wp_}" \
        --allow-root

    wp core install \
        --path="${WP_PATH}" \
        --url="https://${DOMAIN}" \
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_USER}@${DOMAIN}" \
        --skip-email \
        --allow-root

    wp user create "${WP_USER}" "${WP_USER}@${DOMAIN}" \
        --path="${WP_PATH}" \
        --user_pass="${WP_USER_PASS}" \
        --role=author \
        --allow-root

    # php-fpm runs as nobody — hand over ownership
    chown -R nobody:nobody "${WP_PATH}"

    echo "WordPress installation complete."
else
    echo "WordPress already installed."
fi

exec php-fpm84 -F
