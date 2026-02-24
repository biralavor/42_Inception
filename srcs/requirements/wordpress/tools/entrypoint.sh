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
WP_EDITOR=$(sed -n '3p' /run/secrets/credentials)
WP_EDITOR_PASS=$(sed -n '4p' /run/secrets/credentials)

# Non-sensitive config from environment (.env)
# NOTE: WP_USER here is the DB username from .env, not the WP application user
DB_NAME="${WP_DATABASE:-wordpress}"
DB_USER="${WP_USER:-wp_user}"
DB_HOST="${WP_HOST:-mariadb}"
DOMAIN="${DOMAIN_NAME:-localhost}"
WP_PATH="${DOMAIN_ROOT:-/var/www/html}"

# Wait for MariaDB to accept connections (bounded: 30 attempts)
echo "Waiting for MariaDB at ${DB_HOST}..."
i=0
until mysqladmin ping -h "${DB_HOST}" --skip-ssl --silent 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt 30 ] && echo "ERROR: MariaDB not reachable after 30s" && exit 1
    sleep 1
done
echo "MariaDB is ready."

# Check if WordPress is fully installed (not just if wp-config.php exists)
if ! wp core is-installed --path="${WP_PATH}" --allow-root 2>/dev/null; then
    echo "Installing WordPress..."

    # Download core files if not already present
    if [ ! -f "${WP_PATH}/wp-includes/version.php" ]; then
        wp core download \
            --path="${WP_PATH}" \
            --allow-root
    fi

    # Create config if not already present
    if [ ! -f "${WP_PATH}/wp-config.php" ]; then
        wp config create \
            --path="${WP_PATH}" \
            --dbname="${DB_NAME}" \
            --dbuser="${DB_USER}" \
            --dbpass="${DB_PASSWORD}" \
            --dbhost="${DB_HOST}" \
            --dbprefix="${WP_TABLE_PREFIX:-wp_}" \
            --allow-root
    fi

    wp core install \
        --path="${WP_PATH}" \
        --url="https://${DOMAIN}" \
        --title="Inception" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASS}" \
        --admin_email="${WP_ADMIN_USER}@${DOMAIN}" \
        --skip-email \
        --allow-root

    wp user create "${WP_EDITOR}" "${WP_EDITOR}@${DOMAIN}" \
        --path="${WP_PATH}" \
        --user_pass="${WP_EDITOR_PASS}" \
        --role=author \
        --allow-root

    # php-fpm runs as nobody — hand over ownership
    chown -R nobody:nobody "${WP_PATH}"

    echo "WordPress installation complete."
else
    echo "WordPress already installed."
fi

# Bonus setup — runs on every startup when BONUS_SETUP=true.
# Theme/plugin installs are idempotent. Seed import and cast users use flag
# files to prevent duplicate media entries on container restarts.
# Override: BONUS_SETUP=true is injected by `make bonus` at runtime.
if [ "${BONUS_SETUP:-false}" = "true" ]; then
    wp theme install kalpa \
        --path="${WP_PATH}" \
        --activate \
        --allow-root

    wp plugin install elementor \
        --path="${WP_PATH}" \
        --activate \
        --allow-root

    wp plugin install wpkoi-templates-for-elementor \
        --path="${WP_PATH}" \
        --activate \
        --allow-root

    # Import seed images from FTP shared directory if present (once only)
    SEED_FLAG="${WP_PATH}/.seed-imported"
    set -- "${WP_PATH}/wp-content/uploads/seed/"*.jpg
    if [ -f "$1" ] && [ ! -f "${SEED_FLAG}" ]; then
        wp media import "${WP_PATH}/wp-content/uploads/seed/"*.jpg \
            --path="${WP_PATH}" \
            --allow-root || true
        touch "${SEED_FLAG}"
        echo "Seed images imported into WordPress media library."
    else
        echo "No seed images found or already imported — skipping media import."
    fi

    # Create WordPress users from Inception cast images and set profile pictures
    # Cast users have no password by design — display-only subscriber accounts.
    # Flag file prevents duplicate avatar imports on container restarts.
    CAST_SRC="${WP_PATH}/wp-content/uploads/seed"
    CAST_FLAG="${WP_PATH}/.cast-setup-done"
    set -- "${CAST_SRC}"/cast-*.jpeg
    if [ -f "$1" ] && [ ! -f "${CAST_FLAG}" ]; then
        wp plugin install simple-local-avatars \
            --path="${WP_PATH}" \
            --activate \
            --allow-root || true

        for cast_file in "${CAST_SRC}"/cast-*.jpeg; do
            name=$(basename "${cast_file}" .jpeg | sed 's/^cast-//')
            username=$(echo "${name}" | tr '[:upper:]' '[:lower:]')

            wp user create "${username}" "${username}@${DOMAIN}" \
                --display_name="${name}" \
                --role=subscriber \
                --skip-email \
                --path="${WP_PATH}" \
                --allow-root 2>/dev/null || true

            user_id=$(wp user get "${username}" --field=ID \
                --path="${WP_PATH}" --allow-root 2>/dev/null || echo "")
            [ -z "${user_id}" ] && continue

            attach_id=$(wp media import "${cast_file}" \
                --path="${WP_PATH}" \
                --allow-root \
                --porcelain 2>/dev/null || echo "")
            [ -z "${attach_id}" ] && continue

            wp user meta update "${user_id}" simple_local_avatar \
                "{\"full\":${attach_id},\"96\":${attach_id},\"32\":${attach_id}}" \
                --format=json \
                --path="${WP_PATH}" \
                --allow-root || true

            echo "Cast user created: ${name}"
        done
        touch "${CAST_FLAG}"
        echo "Cast users setup complete."
    fi

    # Ensure php-fpm (nobody) owns any files added by bonus setup
    chown -R nobody:nobody "${WP_PATH}"
fi

# Set hero image as featured image of post 1 (idempotent)
webp_seed="${WP_PATH}/wp-content/uploads/seed/Inception-deep-time-tester-object.webp"
if [ -f "${webp_seed}" ]; then
    existing=$(wp post meta get 1 _thumbnail_id \
        --path="${WP_PATH}" --allow-root 2>/dev/null || echo "")
    if [ -z "${existing}" ]; then
        hero_id=$(wp media import "${webp_seed}" \
            --path="${WP_PATH}" \
            --allow-root \
            --porcelain 2>/dev/null || echo "")
        if [ -n "${hero_id}" ]; then
            wp post meta update 1 _thumbnail_id "${hero_id}" \
                --path="${WP_PATH}" --allow-root || true
            echo "Featured image set on post 1 (attachment ${hero_id})."
        else
            echo "Hero image import failed — skipping featured image."
        fi
    else
        echo "Post 1 already has a featured image — skipping."
    fi
fi

exec php-fpm84 -F
